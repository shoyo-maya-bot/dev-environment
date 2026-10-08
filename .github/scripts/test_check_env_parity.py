"""check_env_parity.py のテスト（python -m unittest discover -s .github/scripts）."""

import shutil
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import check_env_parity  # noqa: E402

REAL = Path(__file__).resolve().parents[2] / "cloud" / "environments"

MAIN = """# 環境 {env} の構成
locals {{
  name               = "${{var.system_name}}-{env}"
  enable_nat_gateway = {nat}
}}

module "network" {{
  source             = "../../modules/network"
  name               = local.name
  enable_nat_gateway = local.enable_nat_gateway
}}
"""
VERSIONS = 'provider "aws" {{\n  default_tags {{ tags = {{ Environment = "{env}" }} }}\n}}\n'


class EnvParityTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        for env, nat in (("dev1", "false"), ("stg", "true"), ("prod", "true")):
            d = self.tmp / env
            d.mkdir()
            (d / "main.tf").write_text(MAIN.format(env=env, nat=nat), encoding="utf-8")
            (d / "versions.tf").write_text(VERSIONS.format(env=env), encoding="utf-8")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def edit(self, env, name, old, new):
        p = self.tmp / env / name
        text = p.read_text(encoding="utf-8")
        self.assertIn(old, text)
        p.write_text(text.replace(old, new), encoding="utf-8")

    def test_only_locals_and_env_name_differ(self):
        self.assertEqual(check_env_parity.check(self.tmp), [])

    def test_repository_environments(self):
        # 実際の cloud/environments も約束を守っていること
        self.assertEqual(check_env_parity.check(REAL), [])

    def test_module_argument_only_in_prod_is_reported(self):
        self.edit(
            "prod", "main.tf", "  enable_nat_gateway = local.enable_nat_gateway\n", "  enable_nat_gateway = true\n"
        )
        problems = check_env_parity.check(self.tmp)
        self.assertTrue(any("locals の外" in p and "prod/main.tf" in p for p in problems), problems)

    def test_extra_locals_key_is_reported(self):
        self.edit("stg", "main.tf", "  enable_nat_gateway = true\n", "  enable_nat_gateway = true\n  extra = 1\n")
        problems = check_env_parity.check(self.tmp)
        self.assertTrue(any("locals のキーが違います" in p for p in problems), problems)

    def test_extra_file_is_reported(self):
        (self.tmp / "dev1" / "debug.tf").write_text("# dev1 だけ\n", encoding="utf-8")
        problems = check_env_parity.check(self.tmp)
        self.assertTrue(any("ファイルの一覧が違います" in p and "debug.tf" in p for p in problems), problems)

    def test_other_file_difference_is_reported(self):
        self.edit("stg", "versions.tf", 'Environment = "stg"', 'Environment = "staging"')
        problems = check_env_parity.check(self.tmp)
        self.assertTrue(any("環境名以外" in p for p in problems), problems)

    def test_code_before_locals_is_reported(self):
        self.edit("dev1", "main.tf", "locals {", 'data "x" "y" {}\nlocals {')
        problems = check_env_parity.check(self.tmp)
        self.assertTrue(any("locals より前" in p for p in problems), problems)

    def test_ignores_local_only_files(self):
        (self.tmp / "dev1" / "terraform.tfvars").write_text('bucket_name = "x"\n', encoding="utf-8")
        (self.tmp / "dev1" / ".terraform").mkdir()
        (self.tmp / "dev1" / ".terraform" / "x").write_text("x", encoding="utf-8")
        self.assertEqual(check_env_parity.check(self.tmp), [])

    def test_crlf_is_ignored(self):
        p = self.tmp / "stg" / "main.tf"
        p.write_bytes(p.read_bytes().replace(b"\n", b"\r\n"))
        self.assertEqual(check_env_parity.check(self.tmp), [])


if __name__ == "__main__":
    unittest.main()
