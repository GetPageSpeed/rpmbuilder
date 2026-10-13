"""Tests for ci/image_freshness.py (scheduled-build staleness gate)."""

from datetime import datetime, timedelta, timezone
from pathlib import Path
import sys
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).parents[1] / "ci"))
import image_freshness  # noqa: E402


def iso(dt: datetime) -> str:
    return dt.strftime("%Y-%m-%dT%H:%M:%S.123456789Z")


class ImageFreshnessTest(unittest.TestCase):
    def test_parses_go_nanosecond_timestamps(self) -> None:
        created = image_freshness.parse_created("2026-10-13T14:54:14.839428981Z")
        self.assertEqual(created, datetime(2026, 10, 13, 14, 54, 14, 839428, tzinfo=timezone.utc))

    def test_oldest_platform_wins(self) -> None:
        data = {
            "linux/amd64": {"created": "2026-10-13T14:54:14.839428981Z"},
            "linux/arm64": {"created": "2026-10-10T01:00:00Z"},
        }
        self.assertEqual(image_freshness.oldest_created(data).day, 10)

    def test_single_platform_config(self) -> None:
        data = {"created": "2026-10-13T14:54:14Z"}
        self.assertEqual(image_freshness.oldest_created(data).hour, 14)

    def run_main(self, ages_hours: list[float]) -> int:
        now = datetime.now(timezone.utc)
        data = {f"p{i}": {"created": iso(now - timedelta(hours=h))} for i, h in enumerate(ages_hours)}
        with mock.patch.object(image_freshness, "inspect", return_value=data):
            return image_freshness.main(["img", "--max-age-hours", "24"])

    def test_recent_image_is_fresh(self) -> None:
        self.assertEqual(self.run_main([6, 1]), 0)

    def test_one_stale_platform_makes_image_stale(self) -> None:
        self.assertEqual(self.run_main([1, 30]), 1)

    def test_unknown_age_is_reported_distinctly(self) -> None:
        with mock.patch.object(image_freshness, "inspect", return_value={"linux/amd64": {}}):
            self.assertEqual(image_freshness.main(["img"]), 2)


if __name__ == "__main__":
    unittest.main()
