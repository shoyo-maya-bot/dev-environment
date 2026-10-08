"""cloud/simple/variables.tf の入力検査（validation）のテスト（python -m unittest discover -s .github/scripts）.

後退: allowed_http_cidrs に 0.0.0.0/0 や CIDR でない文字列を渡しても通り、Web（80 番）がインターネット全体に開いた.

variables.tf だけを一時フォルダに写し、terraform console に -var で値を渡して validation を評価する
（provider を使わない. AWS にはつながない. plan / apply はしない）.
SIMPLE_VARIABLES_TERRAFORM（terraform の実行ファイル）が無いとき（versions・windows ジョブ）は飛ばす. CI の terraform ジョブはこれを渡す.
"""

import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

TERRAFORM = os.environ.get("SIMPLE_VARIABLES_TERRAFORM")
VARIABLES = Path(__file__).resolve().parents[2] / "cloud" / "simple" / "variables.tf"


@unittest.skipUnless(TERRAFORM, "SIMPLE_VARIABLES_TERRAFORM が無い（terraform ジョブで実行）")
class AllowedHttpCidrsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.work = tempfile.mkdtemp()
        shutil.copy(VARIABLES, cls.work)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.work, ignore_errors=True)

    def console(self, cidrs):
        """(エラーがあったか, 出力（色の制御文字を除いて改行を詰めたもの）, 値) を返す.

        terraform console は validation の誤りでも終了コード 0 で終わることがあるので、エラーの見出しで判断する.
        """
        r = subprocess.run(  # nosec B603: 決まった terraform に決まった引数を渡すだけ
            [TERRAFORM, f"-chdir={self.work}", "console", "-var", f"allowed_http_cidrs={json.dumps(cidrs)}"],
            input="jsonencode(var.allowed_http_cidrs)\n", capture_output=True, text=True, timeout=120,
            env=dict(os.environ, TF_IN_AUTOMATION="1"),
        )
        text = re.sub(r"\x1b\[[0-9;]*m", "", r.stdout + r.stderr)
        flat = re.sub(r"[\s│╷╵]+", "", text)
        failed = r.returncode != 0 or "Error:" in text
        value = None
        if not failed:
            value = json.loads(json.loads(r.stdout.strip().splitlines()[-1]))
        return failed, flat, value

    def test_accepts_specific_ranges(self):
        for cidrs in (["203.0.113.10/32"], ["198.51.100.0/24", "192.0.2.1/32"]):
            with self.subTest(cidrs=cidrs):
                failed, text, value = self.console(cidrs)
                self.assertFalse(failed, text)
                self.assertEqual(value, cidrs)

    def test_rejects_whole_internet(self):
        for cidrs in (["0.0.0.0/0"], ["::/0"], ["203.0.113.10/32", "0.0.0.0/0"]):
            with self.subTest(cidrs=cidrs):
                failed, text, _ = self.console(cidrs)
                self.assertTrue(failed, text)
                self.assertIn("Invalidvalueforvariable", text)
                self.assertIn("インターネット全体", text)

    def test_rejects_non_cidr(self):
        # CIDR でない・プレフィックス長が無い・範囲外・ホスト部が 0 でない・IPv6（取り込み先は cidr_ipv4）
        for cidrs in (["abc"], ["203.0.113.10"], ["203.0.113.10/33"], ["203.0.113.10/24"], ["2001:db8::/32"], [""]):
            with self.subTest(cidrs=cidrs):
                failed, text, _ = self.console(cidrs)
                self.assertTrue(failed, text)
                self.assertIn("CIDR形式", text)

    def test_rejects_empty_list(self):
        failed, text, _ = self.console([])
        self.assertTrue(failed, text)
        self.assertIn("1つ以上", text)


if __name__ == "__main__":
    unittest.main()
