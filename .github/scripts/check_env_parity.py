#!/usr/bin/env python3
"""環境（cloud/environments/ の dev1 / stg / prod）の差が、決めた場所だけにあることを検査する.

「環境ごとの違いは main.tf 冒頭の locals の値だけ（構造は全環境で同じ）」という約束を、機械で確かめる.
ある環境だけにモジュールや引数を足すと、他の環境で試していない構成が本番に入るので失敗にする.

比べ方:
- 各環境のファイルの一覧が同じであること
- 環境名（dev1 / stg / prod）を <ENV> に置き換えてから、ファイルの中身が全環境で同じであること
  （versions.tf の Environment タグ、backend.hcl.example の key、tfvars の例のバケット名は、この置き換えで同じになる）
- main.tf は、先頭のコメントと最初の locals { ... } を除いた残りが同じであること
- locals のキーの集合が全環境で同じであること（値は違ってよい）

使い方: python .github/scripts/check_env_parity.py [cloud/environments]
終了コード: 0 一致 / 1 locals 以外の差がある（または読み取れない）
"""

from __future__ import annotations

import difflib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DIR = ROOT / "cloud" / "environments"
# 比べないファイル（terraform init で作られるもの・利用者が作る実値のファイル. どれもコミットしない）
IGNORE_DIRS = {".terraform"}
IGNORE_NAMES = {"terraform.tfvars", "backend.hcl", "terraform.tfstate", "terraform.tfstate.backup"}
LOCALS_KEY = re.compile(r"^\s*([A-Za-z_][A-Za-z0-9_-]*)\s*=")


def env_files(env_dir: Path) -> dict[str, str]:
    """環境のディレクトリの中のファイル（相対パス → 中身）."""
    out = {}
    for p in sorted(env_dir.rglob("*")):
        rel = p.relative_to(env_dir)
        if not p.is_file() or IGNORE_DIRS & set(rel.parts) or p.name in IGNORE_NAMES:
            continue
        out[rel.as_posix()] = p.read_text(encoding="utf-8").replace("\r\n", "\n")
    return out


def split_locals(text: str) -> tuple[list[str], str]:
    """main.tf を（locals のキー, 先頭のコメントと最初の locals を除いた残り）に分ける."""
    lines = text.split("\n")
    start = next((i for i, line in enumerate(lines) if re.match(r"^locals\s*\{\s*$", line)), None)
    if start is None:
        raise ValueError("main.tf に locals { がありません（環境の違いは locals に書く約束）")
    if any(line.strip() and not line.lstrip().startswith("#") for line in lines[:start]):
        raise ValueError("main.tf の locals より前に、コメント以外の行があります")
    end = next((i for i in range(start + 1, len(lines)) if lines[i] == "}"), None)
    if end is None:
        raise ValueError("main.tf の locals の閉じ括弧（行頭の }）がありません")
    keys = []
    for line in lines[start + 1 : end]:
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        m = LOCALS_KEY.match(line)
        if not m:
            raise ValueError(f"main.tf の locals の 1 行 1 値の形でない行があります: {line.strip()}")
        keys.append(m.group(1))
    return keys, "\n".join(lines[end + 1 :])


def normalize(text: str, env: str) -> str:
    return re.sub(rf"(?<![A-Za-z0-9_]){re.escape(env)}(?![A-Za-z0-9_])", "<ENV>", text)


def diff(a: str, b: str, name_a: str, name_b: str, limit: int = 20) -> list[str]:
    lines = list(difflib.unified_diff(a.split("\n"), b.split("\n"), name_a, name_b, lineterm="", n=1))
    return [f"      {x}" for x in lines[:limit]] + (["      ..."] if len(lines) > limit else [])


def check(envs_dir: Path) -> list[str]:
    envs = sorted(p.name for p in envs_dir.iterdir() if p.is_dir())
    if len(envs) < 2:
        return [f"{envs_dir}: 環境が 2 つ以上ありません（{envs}）"]
    problems: list[str] = []
    files = {env: env_files(envs_dir / env) for env in envs}
    base = envs[0]
    for env in envs[1:]:
        only_base = sorted(set(files[base]) - set(files[env]))
        only_env = sorted(set(files[env]) - set(files[base]))
        if only_base or only_env:
            problems.append(f"ファイルの一覧が違います: {base} だけ {only_base} / {env} だけ {only_env}")

    keys: dict[str, list[str]] = {}
    bodies: dict[str, dict[str, str]] = {env: {} for env in envs}
    for env in envs:
        for name, text in files[env].items():
            if name == "main.tf":
                try:
                    keys[env], text = split_locals(text)
                except ValueError as e:
                    problems.append(f"{env}/main.tf: {e}")
                    continue
            bodies[env][name] = normalize(text, env)

    for env in envs[1:]:
        if base in keys and env in keys and sorted(keys[base]) != sorted(keys[env]):
            problems.append(
                f"locals のキーが違います: {base} {sorted(keys[base])} / {env} {sorted(keys[env])}"
                "（同じキーを全環境に書き、値だけを変える）"
            )
        for name in sorted(set(bodies[base]) & set(bodies[env])):
            a, b = bodies[base][name], bodies[env][name]
            if a != b:
                where = "locals の外" if name == "main.tf" else "環境名以外"
                problems.append(f"{base}/{name} と {env}/{name} の{where}に差があります:")
                problems += diff(a, b, f"{base}/{name}", f"{env}/{name}")
    return problems


def main(argv: list[str] | None = None) -> int:
    args = sys.argv[1:] if argv is None else argv
    envs_dir = Path(args[0]) if args else DEFAULT_DIR
    try:
        problems = check(envs_dir)
    except OSError as e:
        print(f"NG: {e}")
        return 1
    if problems:
        print("NG: 環境ごとの違いは main.tf の locals の値だけにする約束です（cloud/README.md）")
        for p in problems:
            print(f"  - {p}" if not p.startswith("      ") else p)
        return 1
    envs = ", ".join(sorted(p.name for p in envs_dir.iterdir() if p.is_dir()))
    print(f"OK: 環境（{envs}）の差は locals の値と環境名だけ")
    return 0


if __name__ == "__main__":
    sys.exit(main())
