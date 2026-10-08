"""s3_put_mock.py のテストと、upload-sample.sh をモックに向けて実行するテスト.

実行: python -m unittest discover -s .github/scripts

upload-sample.ps1 は CI の windows ジョブで、同じモックに向けて実際に実行する.
"""

import os
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import s3_put_mock  # noqa: E402

LOCAL = Path(__file__).resolve().parents[2] / "local"


class MockTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.servers = s3_put_mock.make_servers(0, "ci-bucket", self.tmp / "store")
        self.port = self.servers[0].server_address[1]
        for s in self.servers:
            threading.Thread(target=s.serve_forever, daemon=True).start()

    def tearDown(self):
        for s in self.servers:
            s.shutdown()
            s.server_close()
        shutil.rmtree(self.tmp, ignore_errors=True)

    def put(self, path, body=b"x", host="127.0.0.1"):
        req = urllib.request.Request(f"http://{host}:{self.port}{path}", data=body, method="PUT")
        with urllib.request.urlopen(req, timeout=5) as r:  # nosec B310 - 送り先はテスト内で起動したローカルのモック
            return r.status

    def test_listens_on_loopback_only(self):
        hosts = {s.server_address[0] for s in self.servers}
        self.assertIn("127.0.0.1", hosts)
        self.assertTrue(hosts <= {"127.0.0.1", "::1"}, hosts)
        if "::1" in hosts:
            self.assertEqual(self.put("/ci-bucket/v6.csv", host="[::1]"), 200)

    def test_put_stores_body(self):
        self.assertEqual(self.put("/ci-bucket/orders.csv", b"a,b\n"), 200)
        self.assertEqual((self.tmp / "store/ci-bucket/orders.csv").read_bytes(), b"a,b\n")

    def test_other_bucket_is_rejected(self):
        with self.assertRaises(urllib.error.HTTPError) as cm:
            self.put("/sample-bucket/orders.csv")
        self.assertEqual(cm.exception.code, 404)

    def test_path_traversal_is_rejected(self):
        with self.assertRaises(urllib.error.HTTPError) as cm:
            self.put("/ci-bucket/../x")
        self.assertIn(cm.exception.code, (400, 404))

    @unittest.skipUnless(shutil.which("bash") and shutil.which("curl") and os.name != "nt", "bash と curl が必要")
    def test_upload_sample_sh_reads_env_file(self):
        work = self.tmp / "local"
        shutil.copytree(LOCAL / "scripts", work / "scripts")
        shutil.copytree(LOCAL / "data", work / "data")
        (work / ".env").write_text(f"S3_PORT={self.port}\nS3_BUCKET=ci-bucket\n", encoding="utf-8")
        env = {k: v for k, v in os.environ.items() if k not in ("S3_PORT", "S3_BUCKET")}
        r = subprocess.run(
            ["bash", str(work / "scripts/upload-sample.sh")], capture_output=True, text=True, env=env, check=False
        )
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stdout.strip(), "uploaded: s3://ci-bucket/orders.csv")
        self.assertEqual(
            (self.tmp / "store/ci-bucket/orders.csv").read_bytes(), (LOCAL / "data/orders.csv").read_bytes()
        )


if __name__ == "__main__":
    unittest.main()
