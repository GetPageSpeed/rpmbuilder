"""Regression tests for bootstrapping newly introduced repository channels."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class RepoBootstrapTest(unittest.TestCase):
    """Ensure an older builder image can refresh one missing repo definition."""

    def setUp(self) -> None:
        self.build_script = Path(__file__).parents[1] / "assets" / "build"

    def run_helper(self, temp_dir: Path, *, create_on_update: bool) -> subprocess.CompletedProcess[str]:
        """Run the sourced helper with a fake EL7 yum command."""
        etc_dir = temp_dir / "etc"
        share_dir = temp_dir / "share"
        bin_dir = temp_dir / "bin"
        etc_dir.mkdir()
        share_dir.mkdir()
        bin_dir.mkdir()
        yum = bin_dir / "yum"
        marker = temp_dir / "yum-called"
        created_repo = etc_dir / "getpagespeed-extras-php84.repo"
        create_line = (
            f"echo '[getpagespeed-extras-php84]' > {created_repo!s}"
            if create_on_update
            else ":"
        )
        yum.write_text(
            "#!/usr/bin/env bash\n"
            f": > {marker!s}\n"
            f"{create_line}\n"
        )
        yum.chmod(0o755)

        env = os.environ.copy()
        env.update(
            {
                "PATH": f"{bin_dir}:/usr/bin:/bin",
                "RPMBUILDER_HELPERS_ONLY": "1",
                "RPMBUILDER_REPO_ETC_DIR": str(etc_dir),
                "RPMBUILDER_REPO_SHARE_DIR": str(share_dir),
            }
        )
        return subprocess.run(
            [
                "bash",
                "-c",
                'source "$1"; ensure_requested_repo_definition getpagespeed-extras-php84 7',
                "test-repo-bootstrap",
                str(self.build_script),
            ],
            capture_output=True,
            env=env,
            text=True,
        )

    def test_missing_definition_refreshes_release_package(self) -> None:
        """A successful release-package refresh supplies the requested file."""
        with tempfile.TemporaryDirectory() as raw_temp_dir:
            temp_dir = Path(raw_temp_dir)
            result = self.run_helper(temp_dir, create_on_update=True)

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue((temp_dir / "yum-called").exists())
            self.assertTrue((temp_dir / "etc/getpagespeed-extras-php84.repo").exists())

    def test_missing_definition_fails_after_unsuccessful_refresh(self) -> None:
        """The build stops clearly when the requested channel still does not exist."""
        with tempfile.TemporaryDirectory() as raw_temp_dir:
            temp_dir = Path(raw_temp_dir)
            result = self.run_helper(temp_dir, create_on_update=False)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Requested repository definition is unavailable", result.stderr)

    def test_section_inside_shared_repo_file_is_recognized(self) -> None:
        """Channels defined as [sections] of a shared file need no refresh.

        Regression: getpagespeed-extras-mainline lives inside
        getpagespeed-extras.repo, not in its own file. Matching on the file
        name broke every mainline/angie/tengine cohort build (2026-08-14).
        """
        with tempfile.TemporaryDirectory() as raw_temp_dir:
            temp_dir = Path(raw_temp_dir)
            etc_dir = temp_dir / "etc"
            bin_dir = temp_dir / "bin"
            etc_dir.mkdir()
            bin_dir.mkdir()
            (etc_dir / "getpagespeed-extras.repo").write_text(
                "[getpagespeed-extras]\nenabled=1\n"
                "[getpagespeed-extras-mainline]\nenabled=0\n"
            )
            yum = bin_dir / "yum"
            marker = temp_dir / "yum-called"
            yum.write_text(f"#!/usr/bin/env bash\n: > {marker!s}\n")
            yum.chmod(0o755)

            env = os.environ.copy()
            env.update(
                {
                    "PATH": f"{bin_dir}:/usr/bin:/bin",
                    "RPMBUILDER_HELPERS_ONLY": "1",
                    "RPMBUILDER_REPO_ETC_DIR": str(etc_dir),
                    "RPMBUILDER_REPO_SHARE_DIR": str(temp_dir / "no-share"),
                }
            )
            result = subprocess.run(
                [
                    "bash",
                    "-c",
                    'source "$1"; '
                    "ensure_requested_repo_definition getpagespeed-extras-mainline 9",
                    "test-repo-bootstrap",
                    str(self.build_script),
                ],
                capture_output=True,
                env=env,
                text=True,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse((temp_dir / "yum-called").exists())


if __name__ == "__main__":
    unittest.main()
