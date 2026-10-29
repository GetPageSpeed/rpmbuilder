"""Tests for the published-NVR short-circuit on rpm without rpmspec (EL6)."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

QF = "%{NAME}-%{EPOCH}:%{VERSION}-%{RELEASE}.*\\n"


class SpecQueryTest(unittest.TestCase):
    """check_packages_in_repo must work whether or not rpmspec exists."""

    def setUp(self) -> None:
        self.build_script = Path(__file__).parents[1] / "assets" / "build"
        self.temp_dir = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.temp_dir)
        self.bin_dir = self.temp_dir / "bin"
        self.bin_dir.mkdir()
        # Isolated PATH: only these tools plus the fakes below, so a host
        # rpmspec/dnf can never leak into the rpm-4.8 scenario.
        for tool in ("bash", "sed", "cat"):
            (self.bin_dir / tool).symlink_to(shutil.which(tool))
        self.log = self.temp_dir / "calls.log"

    def fake(self, name: str, body: str) -> None:
        path = self.bin_dir / name
        path.write_text(f"#!/bin/sh\nprintf '%s\\n' \"{name} $*\" >> {self.log!s}\n{body}\n")
        path.chmod(0o755)

    def run_check(self) -> subprocess.CompletedProcess[str]:
        env = {
            "PATH": str(self.bin_dir),
            "RPMBUILDER_HELPERS_ONLY": "1",
        }
        return subprocess.run(
            [
                str(self.bin_dir / "bash"),
                "-c",
                'set -eo pipefail; source "$1"; check_packages_in_repo php.spec',
                "test-spec-query",
                str(self.build_script),
            ],
            capture_output=True,
            env=env,
            text=True,
            cwd=self.temp_dir,
        )

    def calls(self) -> str:
        return self.log.read_text() if self.log.exists() else ""

    def test_rpm48_specfile_fallback_short_circuits(self) -> None:
        """Without rpmspec, `rpm -q --specfile` feeds repoquery and all present skips."""
        self.fake("rpm", "printf 'php-(none):5.3.3-51.el6.*\\nphp-cli-(none):5.3.3-51.el6.*\\n'")
        self.fake("repoquery", 'echo "$2"')
        result = self.run_check()

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("All packages from php.spec are present", result.stdout)
        calls = self.calls()
        self.assertIn(f"rpm -q --specfile --qf {QF} php.spec", calls)
        self.assertIn("repoquery -q php-5.3.3-51.el6.*", calls)
        self.assertIn("repoquery -q php-cli-5.3.3-51.el6.*", calls)

    def test_rpm48_missing_package_builds(self) -> None:
        """A NVR absent from the repo still triggers a build on the fallback path."""
        self.fake("rpm", "printf 'php-(none):5.3.3-52.el6.*\\n'")
        self.fake("repoquery", ":")
        result = self.run_check()

        self.assertEqual(result.returncode, 1)
        self.assertIn("php-5.3.3-52.el6.* is NOT present", result.stdout)

    def test_spec_parse_failure_is_not_a_short_circuit(self) -> None:
        """A failing spec query must report failure, never 'all present'."""
        self.fake("rpm", "exit 1")
        self.fake("repoquery", 'echo "$2"')
        result = self.run_check()

        self.assertEqual(result.returncode, 1)
        self.assertIn("Failed to parse spec file php.spec", result.stdout)
        self.assertNotIn("repoquery", self.calls())

    def test_rpmspec_preferred_when_present(self) -> None:
        """rpm >= 4.9 images keep using rpmspec."""
        self.fake("rpmspec", "printf 'nginx-1:1.30.0-1.el9.*\\n'")
        self.fake("rpm", "exit 99")
        self.fake("repoquery", 'echo "$2"')
        result = self.run_check()

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        calls = self.calls()
        self.assertIn(f"rpmspec -q --qf {QF} php.spec", calls)
        self.assertNotIn("rpm -q", calls)
        self.assertIn("repoquery -q nginx-1:1.30.0-1.el9.*", calls)


if __name__ == "__main__":
    unittest.main()
