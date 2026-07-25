"""Regression tests for private-source credential handling."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class CredentialTraceTest(unittest.TestCase):
    """Ensure shell tracing cannot disclose GitHub credentials."""

    def test_token_is_not_traced(self) -> None:
        """Run credential setup under xtrace without exposing the token."""
        sentinel = "ghp_NEVER_PRINT_THIS_SENTINEL"
        build_script = Path(__file__).parents[1] / "assets" / "build"

        with tempfile.TemporaryDirectory() as temp_dir:
            netrc_path = Path(temp_dir) / "netrc"
            curlrc_path = Path(temp_dir) / "curlrc"
            env = os.environ.copy()
            env.update(
                {
                    "RPMBUILDER_HELPERS_ONLY": "1",
                    "RPMBUILDER_NETRC_PATH": str(netrc_path),
                    "RPMBUILDER_CURLRC_PATH": str(curlrc_path),
                    "GITHUB_API_TOKEN": sentinel,
                }
            )
            result = subprocess.run(
                [
                    "bash",
                    "-x",
                    "-c",
                    'source "$1"; configure_github_credentials',
                    "test-credentials",
                    str(build_script),
                ],
                check=True,
                capture_output=True,
                env=env,
                text=True,
            )

            self.assertNotIn(sentinel, result.stderr)
            self.assertIn(sentinel, netrc_path.read_text())
            self.assertEqual(curlrc_path.read_text(), "--netrc\n")


if __name__ == "__main__":
    unittest.main()
