"""check_versions.py のテスト（python -m unittest discover -s .github/scripts）."""

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import check_versions  # noqa: E402

BUILD = """plugins {
    id 'org.springframework.boot' version '4.1.1'
}
tasks.withType(JavaCompile).configureEach {
    options.release = 17
}
dependencies {
    implementation 'org.mybatis.spring.boot:mybatis-spring-boot-starter:4.1.0'
}
"""
WRAPPER = "distributionUrl=https\\://services.gradle.org/distributions/gradle-9.8.0-bin.zip\n"
README_OK = """| 言語・FW | Java 17、Spring Boot 4.1、MyBatis（mybatis-spring-boot-starter 4.1） |
| ビルド | Gradle 9.8（Wrapper で固定） |
"""
LOCAL_OK = """| Java | Amazon Corretto | 17（本番と同じ） | x |
| ビルド | Gradle | Wrapper で 9.8 系に固定 | x |
"""


def make_repo(root: Path, readme: str, local: str) -> None:
    (root / "sample-app/gradle/wrapper").mkdir(parents=True)
    (root / "local").mkdir()
    (root / "sample-app/build.gradle").write_text(BUILD, encoding="utf-8")
    (root / "sample-app/gradle/wrapper/gradle-wrapper.properties").write_text(WRAPPER, encoding="utf-8")
    (root / "README.md").write_text(readme, encoding="utf-8")
    (root / "local/README.md").write_text(local, encoding="utf-8")


class CheckVersionsTest(unittest.TestCase):
    def run_check(self, readme: str, local: str = LOCAL_OK) -> list[str]:
        with tempfile.TemporaryDirectory() as d:
            make_repo(Path(d), readme, local)
            return check_versions.check(Path(d))

    def test_ok(self):
        self.assertEqual(self.run_check(README_OK), [])

    def test_old_versions_in_readme_are_reported(self):
        # 採点で見つかったずれ: README は Boot 4.0・MyBatis 4.0・Gradle 8.14、実物は 4.1.1・4.1.0・9.8.0
        old = README_OK.replace("Spring Boot 4.1", "Spring Boot 4.0").replace("starter 4.1", "starter 4.0").replace(
            "Gradle 9.8", "Gradle 8.14"
        )
        errors = self.run_check(old)
        self.assertEqual(len(errors), 3, errors)
        self.assertTrue(any("spring-boot を 4.0" in e for e in errors))
        self.assertTrue(any("gradle を 8.14" in e for e in errors))

    def test_local_readme_patch_version_is_reported(self):
        errors = self.run_check(README_OK, LOCAL_OK.replace("9.8 系", "8.14.3 系"))
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("local/README.md:2", errors[0])

    def test_missing_claim_fails_instead_of_passing(self):
        errors = self.run_check("| 言語・FW | Java 17、 |\n")
        self.assertTrue(any("見つかりません" in e for e in errors), errors)

    def test_full_version_is_accepted(self):
        self.assertEqual(self.run_check(README_OK.replace("Spring Boot 4.1", "Spring Boot 4.1.1")), [])


if __name__ == "__main__":
    unittest.main()
