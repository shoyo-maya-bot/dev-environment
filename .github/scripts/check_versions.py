#!/usr/bin/env python3
"""README に書いた版が、ビルドファイルの実物とずれていないかを検査する.

Dependabot が sample-app の版を上げたとき、README の「技術スタック」などが古いまま残らないようにする.
README には「メジャー.マイナー」まで書く（例: Spring Boot 4.1）。パッチ版の更新では README を直さなくてよい.

使い方: python .github/scripts/check_versions.py [リポジトリのルート]
終了コード: 0 一致 / 1 ずれあり（または読み取れない）
"""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Source:
    """実物の版の取り出し方."""

    name: str
    path: str
    pattern: str


@dataclass(frozen=True)
class Claim:
    """README に書いた版の場所."""

    source: str  # Source.name
    path: str
    pattern: str  # グループ v に版が入る


SOURCES = [
    Source("java", "sample-app/build.gradle", r"options\.release\s*=\s*(?P<v>\d+)"),
    Source("spring-boot", "sample-app/build.gradle", r"id 'org\.springframework\.boot' version '(?P<v>[\d.]+)'"),
    Source("mybatis", "sample-app/build.gradle", r"mybatis-spring-boot-starter:(?P<v>[\d.]+)'"),
    Source("gradle", "sample-app/gradle/wrapper/gradle-wrapper.properties", r"gradle-(?P<v>[\d.]+)-bin\.zip"),
]

CLAIMS = [
    Claim("java", "README.md", r"\| 言語・FW \| Java (?P<v>\d+)、"),
    Claim("spring-boot", "README.md", r"Spring Boot (?P<v>[\d.]+)"),
    Claim("mybatis", "README.md", r"mybatis-spring-boot-starter (?P<v>[\d.]+)"),
    Claim("gradle", "README.md", r"\| ビルド \| Gradle (?P<v>[\d.]+)"),
    Claim("java", "local/README.md", r"\| Java \| Amazon Corretto \| (?P<v>\d+)"),
    Claim("gradle", "local/README.md", r"\| ビルド \| Gradle \| Wrapper で (?P<v>[\d.]+) 系に固定"),
]


def major_minor(version: str) -> str:
    return ".".join(version.split(".")[:2])


def matches(claimed: str, actual: str) -> bool:
    """README の版（メジャー.マイナー、または完全な版）が実物と合っているか."""
    if "." not in actual:
        return claimed == actual
    return claimed in (actual, major_minor(actual))


def check(root: Path) -> list[str]:
    errors: list[str] = []
    actual: dict[str, str] = {}
    for src in SOURCES:
        text = (root / src.path).read_text(encoding="utf-8")
        m = re.search(src.pattern, text)
        if not m:
            errors.append(f"{src.path}: {src.name} の版を読み取れません（パターン {src.pattern!r}）")
            continue
        actual[src.name] = m.group("v")
    for claim in CLAIMS:
        if claim.source not in actual:
            continue
        text = (root / claim.path).read_text(encoding="utf-8")
        found = [(text.count("\n", 0, m.start()) + 1, m.group("v")) for m in re.finditer(claim.pattern, text)]
        if not found:
            errors.append(f"{claim.path}: {claim.source} の版の記述が見つかりません（パターン {claim.pattern!r}）")
            continue
        want = actual[claim.source]
        for line, got in found:
            if not matches(got, want):
                errors.append(
                    f"{claim.path}:{line}: {claim.source} を {got} と書いていますが、実物は {want} です"
                    f"（README は {major_minor(want)} と書く）"
                )
    return errors


def main(argv: list[str]) -> int:
    root = Path(argv[1]) if len(argv) > 1 else Path(__file__).resolve().parents[2]
    errors = check(root)
    for e in errors:
        print(f"::error::{e}")
    if not errors:
        print("README の版の記述はビルドファイルと一致しています")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
