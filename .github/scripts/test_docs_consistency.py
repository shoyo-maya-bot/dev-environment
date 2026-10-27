"""README に書いた値と、コード・設定の実物が一致することのテスト（python -m unittest discover -s .github/scripts）.

ドキュメントと実際の動きのずれを機械で見つける. 見ているもの:
- バッチの終了コード: sample-app の定数（BatchJob の OK / WARN / ERROR、OrderImportJob の CONFLICT）と、
  README.md の「バッチの終了コード」、local/README.md の終了コードの表、cloud/README.md のジョブフローの表
- 環境の違い: cloud/README.md の環境の表（NAT・VPC エンドポイント・DB 台数・削除保護・最終スナップショット・API 台数）と、
  cloud/environments/<環境>/main.tf の locals の値. locals に足したキーが表に無いときも失敗にする

後退: 第 6 回までに、aurora-postgres の最終スナップショットが削除保護と連動しているのに README に書かれていなかった、
local/README.md の終了コード 8 の表にジョブ ID の誤り（APPE0006）が無かった、などのずれがあった.
"""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
JAVA = ROOT / "sample-app" / "src" / "main" / "java" / "com" / "example" / "sample"


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8").replace("\r\n", "\n")


def int_constants(path: Path) -> dict[str, int]:
    """Java の `int NAME = 数字;`（static final を含む）を取り出す."""
    text = path.read_text(encoding="utf-8")
    return {m.group(1): int(m.group(2)) for m in re.finditer(r"\bint\s+([A-Z_]+)\s*=\s*(\d+)\s*;", text)}


def table_after(text: str, heading_pattern: str) -> list[list[str]]:
    """見出し（正規表現）の後にある最初の Markdown の表を、行ごとのセルの一覧で返す（見出し行と区切り行を除く）."""
    m = re.search(heading_pattern, text, re.M)
    if m is None:
        raise AssertionError(f"見出し {heading_pattern!r} が見つかりません")
    rows: list[list[str]] = []
    started = False
    for line in text[m.end():].split("\n"):
        if line.startswith("|"):
            started = True
            rows.append([c.strip() for c in line.strip().strip("|").split("|")])
        elif started:
            break
    if len(rows) < 3:
        raise AssertionError(f"{heading_pattern!r} の後に表がありません")
    return [rows[0]] + rows[2:]


def locals_values(main_tf: str) -> dict[str, str]:
    """main.tf の最初の locals { ... } の `キー = 値` を返す."""
    m = re.search(r"^locals \{\n(.*?)^\}", main_tf, re.M | re.S)
    if m is None:
        raise AssertionError("main.tf に locals がありません")
    out = {}
    for line in m.group(1).split("\n"):
        kv = re.match(r"^\s*([a-z_0-9]+)\s*=\s*(.+?)\s*$", line)
        if kv:
            out[kv.group(1)] = kv.group(2)
    return out


class ExitCodesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        batch = int_constants(JAVA / "batch" / "BatchJob.java")
        job = int_constants(JAVA / "order" / "batch" / "OrderImportJob.java")
        cls.codes = {batch["OK"], batch["WARN"], batch["ERROR"], job["CONFLICT"]}

    def test_constants_are_the_documented_set(self):
        self.assertEqual(self.codes, {0, 4, 6, 8})

    def test_readme_conventions(self):
        row = next(line for line in read("README.md").split("\n") if line.startswith("| バッチの終了コード |"))
        written = {int(c) for c in re.findall(r"(?:^|/)\s*(\d+)\s", row.split("|")[2])}
        self.assertEqual(written, self.codes, row)

    def test_local_readme_table(self):
        rows = table_after(read("local/README.md"), r"^\*\*終了コード\*\*:")
        self.assertEqual(rows[0][0], "終了コード")
        self.assertEqual({int(r[0]) for r in rows[1:]}, self.codes)
        by_code = {int(r[0]): r for r in rows[1:]}
        # ジョブ ID の誤り（BatchJobGuard）は 8 と APPE0006
        self.assertIn("ジョブ ID", by_code[8][1])
        self.assertIn("APPE0006", by_code[8][2])

    def test_cloud_readme_workflow_table(self):
        rows = table_after(read("cloud/README.md"), r"^## バッチのジョブフロー")
        written = {int(c) for r in rows[1:] for c in re.findall(r"\d+", r[0])}
        self.assertLessEqual(self.codes, written)
        results = {int(re.match(r"\d+", r[0]).group()): r[2] for r in rows[1:] if re.match(r"\d+", r[0])}
        self.assertIn("Succeeded", results[0])
        self.assertIn("SucceededWithWarning", results[4])
        self.assertIn("JobFailed", results[6])
        self.assertIn("JobFailed", results[8])


class EnvironmentTableTest(unittest.TestCase):
    # 表の列 → (locals のキー, 表の書き方 → locals の値)
    COLUMNS = {
        "NAT": ("enable_nat_gateway", {"あり": "true", "なし": "false"}),
        "VPC エンドポイント": ("enable_vpc_endpoints", {"あり": "true", "なし": "false"}),
        "DB 台数": ("db_instance_count", None),
        "削除保護": ("protect_data", {"あり": "true", "なし": "false"}),
        "最終スナップショット": ("skip_db_final_snapshot", {"取る": "false", "取らない": "true"}),
        "API 台数": ("api_desired_count", None),
    }
    # 表に載せない locals（環境名から決まるもの）
    NOT_IN_TABLE = {"name"}

    @classmethod
    def setUpClass(cls):
        rows = table_after(read("cloud/README.md"), r"^環境の違いは各環境の `main.tf` 冒頭の `locals`")
        cls.header = rows[0]
        cls.rows = {r[0]: dict(zip(rows[0], r)) for r in rows[1:]}
        envs_dir = ROOT / "cloud" / "environments"
        cls.envs = {p.name: locals_values((p / "main.tf").read_text(encoding="utf-8")) for p in envs_dir.iterdir() if p.is_dir()}

    def test_every_environment_has_a_row(self):
        self.assertEqual(set(self.rows), set(self.envs))

    def test_every_locals_key_is_documented(self):
        documented = {key for key, _ in self.COLUMNS.values()} | self.NOT_IN_TABLE
        for env, values in self.envs.items():
            with self.subTest(env=env):
                self.assertEqual(set(values) - documented, set(), "cloud/README.md の環境の表に列を足してください")
        self.assertEqual(self.header[1:], list(self.COLUMNS))

    def test_values_match_locals(self):
        for env, values in self.envs.items():
            for column, (key, mapping) in self.COLUMNS.items():
                with self.subTest(env=env, column=column):
                    cell = self.rows[env][column]
                    if mapping is None:
                        written = re.match(r"\d+", cell).group()
                    else:
                        written = next((v for k, v in sorted(mapping.items(), key=lambda kv: -len(kv[0])) if cell.startswith(k)), None)
                    self.assertEqual(written, values[key], f"cloud/README.md の {env} の「{column}」は {cell}、locals の {key} は {values[key]}")


if __name__ == "__main__":
    unittest.main()
