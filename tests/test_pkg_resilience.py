"""Tests for assets/transient/pkg-resilience.sh (retry + EL origin fallback)."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).parents[1]
HELPERS = ROOT / "assets" / "transient" / "pkg-resilience.sh"
ALMA_FIXTURE = ROOT / "tests" / "fixtures" / "almalinux-8.repo"


class PkgResilienceTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp)
        self.repo_dir = self.tmp / "yum.repos.d"
        self.repo_dir.mkdir()
        self.alma = self.repo_dir / "almalinux.repo"
        shutil.copy(ALMA_FIXTURE, self.alma)
        # A third-party repo must never be touched by the fallback.
        self.epel = self.repo_dir / "epel.repo"
        self.epel.write_text(
            "[epel]\nmetalink=https://mirrors.fedoraproject.org/metalink\n"
            "#baseurl=https://download.example/pub/epel/8/\n"
        )
        self.bin_dir = self.tmp / "bin"
        self.bin_dir.mkdir()
        self.log = self.tmp / "calls.log"

    def run_bash(self, script: str) -> subprocess.CompletedProcess[str]:
        env = os.environ.copy()
        env.update(
            EL_REPO_DIR=str(self.repo_dir),
            RETRY_SLEEP="0",
            PATH=f"{self.bin_dir}:{env['PATH']}",
        )
        return subprocess.run(
            ["bash", "-c", f"set -euo pipefail; . {HELPERS}; {script}"],
            env=env, capture_output=True, text=True, check=False,
        )

    def fake_dnf(self, succeed_on_origin: bool) -> None:
        """dnf that fails while BaseOS still uses the mirrorlist (stale pool)."""
        body = "exit 1" if not succeed_on_origin else (
            f"grep -q '^baseurl=https://repo.almalinux.org/almalinux/\\$releasever/BaseOS' "
            f"{self.alma} && exit 0 || exit 1"
        )
        dnf = self.bin_dir / "dnf"
        dnf.write_text(
            "#!/usr/bin/env bash\n"
            f'echo "$*" >> {self.log}\n'
            'if [ "$1" = clean ]; then exit 0; fi\n'
            f"{body}\n"
        )
        dnf.chmod(0o755)

    def test_switch_activates_origin_only_in_mirrorlist_sections(self) -> None:
        result = self.run_bash("el_switch_to_origin")
        self.assertEqual(result.returncode, 0, result.stderr)
        text = self.alma.read_text()
        self.assertNotRegex(text, r"(?m)^mirrorlist=")
        self.assertIn(
            "\nbaseurl=https://repo.almalinux.org/almalinux/$releasever/BaseOS/$basearch/os/\n",
            text,
        )
        self.assertEqual(
            self.epel.read_text().count("#baseurl="), 1, "non-vendor repo was modified"
        )

    def test_restore_is_byte_identical(self) -> None:
        original = self.alma.read_bytes()
        epel_original = self.epel.read_bytes()
        result = self.run_bash("el_switch_to_origin; el_restore_mirrorlist")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.alma.read_bytes(), original)
        self.assertEqual(self.epel.read_bytes(), epel_original)

    def test_restore_without_switch_is_noop(self) -> None:
        original = self.alma.read_bytes()
        result = self.run_bash("el_restore_mirrorlist")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.alma.read_bytes(), original)

    def test_retry_recovers_stale_mirror_pool_via_origin(self) -> None:
        """Regression: 2026-10-13 almalinux:8 arm64 stale-repomd failure."""
        self.fake_dnf(succeed_on_origin=True)
        result = self.run_bash("retry 5 dnf -y install dnf-plugins-core; el_restore_mirrorlist")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        calls = self.log.read_text().splitlines()
        self.assertIn("clean metadata", calls)
        # attempt 1 + 2 on the pool, attempt 3 on origin succeeds
        self.assertEqual(sum(c.startswith("-y install") for c in calls), 3)
        self.assertEqual(self.alma.read_bytes(), ALMA_FIXTURE.read_bytes())

    def test_retry_gives_up_after_max_attempts(self) -> None:
        self.fake_dnf(succeed_on_origin=False)
        result = self.run_bash("retry 3 dnf -y install foo")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("All 3 attempts failed", result.stdout)

    def test_retry_leaves_repos_alone_for_non_pkg_commands(self) -> None:
        original = self.alma.read_bytes()
        result = self.run_bash("retry 3 false || true")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.alma.read_bytes(), original)


if __name__ == "__main__":
    unittest.main()
