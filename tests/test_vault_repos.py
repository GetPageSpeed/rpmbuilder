"""Tests for assets/transient/vault-repos.sh (multi-mirror EL6/EL7 vault repos)."""

import configparser
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).parents[1]
SCRIPT = ROOT / "assets" / "transient" / "vault-repos.sh"
FIX_REPOS = ROOT / "assets" / "transient" / "fix-repos.sh"
SETUP = ROOT / "assets" / "transient" / "setup.sh"

FILES = ("CentOS-Base.repo", "CentOS-SCLo-scl.repo", "CentOS-SCLo-scl-rh.repo", "epel.repo")
ENABLED = {
    "CentOS-Base.repo": ("base", "updates", "extras"),
    "CentOS-SCLo-scl.repo": ("centos-sclo-sclo",),
    "CentOS-SCLo-scl-rh.repo": ("centos-sclo-rh",),
    "epel.repo": ("epel",),
}


class VaultReposTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp)

    def render(self, rhel: str, arch: str, amzn: str = "0", what: str = "all"):
        env = os.environ.copy()
        env.update(VAULT_REPO_DIR=str(self.tmp), VAULT_RHEL=rhel,
                   VAULT_ARCH=arch, VAULT_AMZN=amzn)
        return subprocess.run(["bash", str(SCRIPT), what], env=env,
                              capture_output=True, text=True, check=False)

    def parse(self, name: str) -> configparser.RawConfigParser:
        # yum's iniparse reads indented continuation lines the same way.
        cp = configparser.RawConfigParser()
        cp.read(self.tmp / name)
        return cp

    def baseurls(self, name: str, section: str) -> list[str]:
        return self.parse(name)[section]["baseurl"].split()

    def assert_failover(self, rhel: str, arch: str) -> None:
        self.assertEqual(self.render(rhel, arch).returncode, 0)
        for name in FILES:
            for section in ENABLED[name]:
                cp = self.parse(name)
                self.assertEqual(cp[section]["enabled"], "1", (name, section))
                self.assertEqual(cp[section]["failovermethod"], "priority", (name, section))
                urls = self.baseurls(name, section)
                self.assertGreaterEqual(len(urls), 5, (name, section))
                self.assertEqual(len(set(urls)), len(urls))
                # Cloudflare front first, our own slot second, rest non-CF.
                self.assertRegex(urls[0], r"^https://(vault|archive)\.epel\.cloud/")
                self.assertTrue(urls[1].startswith("https://vault.getpagespeed.com/"))
                for url in urls[2:]:
                    self.assertNotIn("epel.cloud", url)

    def test_el7_x86_64(self) -> None:
        self.assert_failover("7", "x86_64")
        urls = self.baseurls("CentOS-Base.repo", "base")
        self.assertEqual(urls[0], "https://vault.epel.cloud/7.9.2009/os/$basearch/")
        self.assertIn("https://vault.centos.org/7.9.2009/os/$basearch/", urls)
        self.assertEqual(self.baseurls("CentOS-SCLo-scl-rh.repo", "centos-sclo-rh")[2],
                         "https://ftp.iij.ad.jp/pub/linux/centos-vault/7.9.2009/sclo/$basearch/rh/")
        self.assertEqual(self.baseurls("epel.repo", "epel")[0],
                         "https://archive.epel.cloud/pub/archive/epel/7/$basearch")
        self.assertIn("RPM-GPG-KEY-CentOS-7\n", (self.tmp / "CentOS-Base.repo").read_text())
        self.assertEqual(self.parse("CentOS-Base.repo")["centosplus"]["enabled"], "0")

    def test_el7_aarch64_uses_altarch_everywhere(self) -> None:
        self.assert_failover("7", "aarch64")
        for name in FILES[:3]:
            for section in ENABLED[name]:
                for url in self.baseurls(name, section):
                    self.assertIn("/altarch/7.9.2009/", url)
        self.assertIn("RPM-GPG-KEY-CentOS-7-aarch64", (self.tmp / "CentOS-Base.repo").read_text())

    def test_el6(self) -> None:
        self.assert_failover("6", "x86_64")
        self.assertEqual(self.baseurls("CentOS-Base.repo", "updates")[0],
                         "https://vault.epel.cloud/6.10/updates/$basearch/")
        self.assertTrue(self.baseurls("epel.repo", "epel")[3].endswith("/epel/6/$basearch"))

    def test_rpm_style_zero_padded_rhel(self) -> None:
        self.assertEqual(self.render("07", "x86_64").returncode, 0)
        self.assertTrue((self.tmp / "CentOS-Base.repo").exists())

    def test_amazon_linux_and_other_els_untouched(self) -> None:
        for rhel, amzn in (("7", "2"), ("8", "0"), ("0", "0")):
            self.assertEqual(self.render(rhel, "x86_64", amzn).returncode, 0)
        self.assertEqual(list(self.tmp.iterdir()), [])

    def test_subcommands_write_only_their_files(self) -> None:
        self.assertEqual(self.render("6", "x86_64", what="scl").returncode, 0)
        self.assertEqual(sorted(p.name for p in self.tmp.iterdir()),
                         ["CentOS-SCLo-scl-rh.repo", "CentOS-SCLo-scl.repo"])
        self.assertEqual(self.render("6", "x86_64", what="bogus").returncode, 2)

    def test_image_build_wires_the_writer(self) -> None:
        self.assertIn("vault-repos.sh all", FIX_REPOS.read_text())
        setup = SETUP.read_text()
        self.assertNotIn("getpagespeed.com/files/centos6", setup)
        for what in ("base", "scl", "epel"):
            self.assertIn(f"vault-repos.sh {what}", setup)


if __name__ == "__main__":
    unittest.main()
