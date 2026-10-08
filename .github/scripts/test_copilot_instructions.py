""".github/copilot-instructions.md の必須項目のテスト（python -m unittest discover -s .github/scripts）.

後退: 指示に「apply は自分で実行しない」しか無く、plan・destroy・state の操作や AWS への接続、止まる条件が書かれていなかった.
費用・共有の state・クラウドに触れる操作と、止まって人に確かめる条件が、消えずに残っていることを確かめる.
"""

import re
import unittest
from pathlib import Path

PATH = Path(__file__).resolve().parents[1] / "copilot-instructions.md"


class CopilotInstructionsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = PATH.read_text(encoding="utf-8")

    def section(self, heading):
        m = re.search(rf"^## {re.escape(heading)}\n(.*?)(?=^## |\Z)", self.text, re.M | re.S)
        self.assertIsNotNone(m, f"見出し「## {heading}」がありません")
        return m.group(1)

    def test_operations_requiring_explicit_instruction(self):
        body = self.section("人の明示の指示なしにしない操作（費用・共有の state・クラウドに触れるもの）")
        for op in ("terraform plan", "terraform apply", "terraform destroy", "terraform state", "force-unlock",
                   "aws", "start-execution", "git push --force"):
            with self.subTest(op=op):
                self.assertIn(op, body)
        self.assertIn("明示", body)

    def test_safe_checks_do_not_include_cloud_operations(self):
        body = self.section("してよい確認（AWS にはつながない）")
        self.assertIn("-backend=false", body)
        for op in ("terraform plan", "terraform apply", "terraform destroy", "aws "):
            with self.subTest(op=op):
                self.assertNotIn(op, body)

    def test_stop_conditions(self):
        body = self.section("止まって人に確かめる条件")
        items = re.findall(r"^\d+\. ", body, re.M)
        self.assertGreaterEqual(len(items), 4)
        for word in ("認証情報", "費用", "削除", "prod"):
            with self.subTest(word=word):
                self.assertIn(word, body)

    def test_untrusted_content_is_data(self):
        self.assertIn("データとして扱う", self.text)


if __name__ == "__main__":
    unittest.main()
