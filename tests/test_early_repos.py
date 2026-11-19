"""Tests for EARLY_REPOS: nginx cohort lanes resolve against the early channel."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest

EXTRAS_REPO = (
    "[getpagespeed-extras]\nenabled=1\n"
    "[getpagespeed-extras-early]\nenabled=0\n"
    "[getpagespeed-extras-early-noarch]\nenabled=0\n"
    "[getpagespeed-extras-mainline]\nenabled=0\n"
    "[getpagespeed-extras-mainline-early]\nenabled=0\n"
)


class EarlyReposTest(unittest.TestCase):
    """The early twin of the effective channel is enabled when it is defined."""

    def setUp(self) -> None:
        self.build_script = Path(__file__).parents[1] / "assets" / "build"

    def run_enable(
        self, temp_dir: Path, repo_id: str, rhel: str, *, tool: str
    ) -> subprocess.CompletedProcess[str]:
        """Run enable_early_repos with a fake config-manager tool on PATH.

        Args:
            temp_dir: Scratch directory holding the fake repo files and tools.
            repo_id: The channel a lane enables, or "" for the base channel.
            rhel: The value of %rhel in the image, "0" on Fedora.
            tool: Which fake tool to provide: "yum-config-manager" or "dnf".

        Returns:
            The completed helper process; calls are logged to `calls`.
        """
        etc_dir = temp_dir / "etc"
        bin_dir = temp_dir / "bin"
        etc_dir.mkdir()
        bin_dir.mkdir()
        (etc_dir / "getpagespeed-extras.repo").write_text(EXTRAS_REPO)
        (etc_dir / "getpagespeed-extras-plesk.repo").write_text(
            "[getpagespeed-extras-plesk]\nenabled=0\n"
        )
        calls = temp_dir / "calls"
        for name in (tool, "yum"):
            fake = bin_dir / name
            fake.write_text(f'#!/usr/bin/env bash\necho "{name} $*" >> {calls!s}\n')
            fake.chmod(0o755)

        env = os.environ.copy()
        env.update(
            {
                "PATH": f"{bin_dir}:/usr/bin:/bin",
                "RPMBUILDER_HELPERS_ONLY": "1",
                "RPMBUILDER_REPO_ETC_DIR": str(etc_dir),
                "RPMBUILDER_REPO_SHARE_DIR": str(temp_dir / "no-share"),
            }
        )
        return subprocess.run(
            [
                "bash",
                "-c",
                'source "$1"; enable_early_repos "$2" "$3"',
                "test-early-repos",
                str(self.build_script),
                repo_id,
                rhel,
            ],
            capture_output=True,
            env=env,
            text=True,
        )

    def test_base_channel_enables_arch_and_noarch_twins(self) -> None:
        """No ENABLE_REPOS means the base channel: both early twins go on."""
        with tempfile.TemporaryDirectory() as raw_temp_dir:
            temp_dir = Path(raw_temp_dir)
            result = self.run_enable(temp_dir, "", "9", tool="dnf")

            self.assertEqual(result.returncode, 0, result.stderr)
            calls = (temp_dir / "calls").read_text().splitlines()
            self.assertEqual(
                calls,
                [
                    "dnf config-manager --set-enabled getpagespeed-extras-early",
                    "dnf config-manager --set-enabled "
                    "getpagespeed-extras-early-noarch",
                ],
            )

    def test_sub_channel_enables_its_own_twin_on_el7(self) -> None:
        """A sub-channel lane enables <id>-early, through yum on EL7."""
        with tempfile.TemporaryDirectory() as raw_temp_dir:
            temp_dir = Path(raw_temp_dir)
            result = self.run_enable(
                temp_dir,
                "getpagespeed-extras-mainline",
                "7",
                tool="yum-config-manager",
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                (temp_dir / "calls").read_text().splitlines(),
                ["yum-config-manager --enable getpagespeed-extras-mainline-early"],
            )

    def test_channel_without_early_twin_is_skipped(self) -> None:
        """A channel with no early twin builds on; nothing gets enabled."""
        with tempfile.TemporaryDirectory() as raw_temp_dir:
            temp_dir = Path(raw_temp_dir)
            result = self.run_enable(
                temp_dir, "getpagespeed-extras-plesk", "9", tool="dnf"
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(
                "No early repository getpagespeed-extras-plesk-early", result.stdout
            )
            calls = (temp_dir / "calls").read_text()
            self.assertNotIn("config-manager", calls)


if __name__ == "__main__":
    unittest.main()
