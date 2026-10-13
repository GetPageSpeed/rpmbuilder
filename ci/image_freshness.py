#!/usr/bin/env python3
"""Decide whether a published rpmbuilder image is still fresh enough.

Scheduled CI rebuilds every image every 6 hours. A single failed rebuild
(upstream mirror lag, registry blip) leaves the previous image serving and
needs no human, so the workflow only fails a scheduled run once the published
image is older than --max-age-hours. Freshness is read from the registry
(image config "created", oldest platform wins) because hub.docker.com's web API
sits behind a Cloudflare challenge.

Exit codes: 0 fresh, 1 stale, 2 age unknown (treat as stale).
"""

import argparse
from datetime import datetime, timedelta, timezone
import json
import subprocess
import sys


def parse_created(value: str) -> datetime:
    # Go timestamps carry nanoseconds; Python handles at most microseconds.
    value = value.replace("Z", "+00:00")
    if "." in value:
        head, rest = value.split(".", 1)
        frac, sep, tz = rest.partition("+")
        value = f"{head}.{frac[:6]}{sep}{tz}"
    return datetime.fromisoformat(value)


def oldest_created(image_json: dict) -> datetime:
    """`imagetools inspect --format '{{json .Image}}'`: per-platform or single."""
    if "created" in image_json:
        configs = [image_json]
    else:
        configs = list(image_json.values())
    stamps = [parse_created(c["created"]) for c in configs if c.get("created")]
    if not stamps:
        raise ValueError("no created timestamp in image config")
    return min(stamps)


def inspect(image: str) -> dict:
    out = subprocess.run(
        ["docker", "buildx", "imagetools", "inspect", image, "--format", "{{json .Image}}"],
        check=True, capture_output=True, text=True,
    ).stdout
    return json.loads(out)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("image")
    parser.add_argument("--max-age-hours", type=float, default=24)
    args = parser.parse_args(argv)
    try:
        created = oldest_created(inspect(args.image))
    except (subprocess.CalledProcessError, ValueError, KeyError, json.JSONDecodeError) as exc:
        print(f"::warning::cannot determine age of {args.image}: {exc}")
        return 2
    age = datetime.now(timezone.utc) - created
    hours = age / timedelta(hours=1)
    print(f"{args.image} built {created.isoformat()} ({hours:.1f}h ago, limit {args.max_age_hours:g}h)")
    return 0 if hours <= args.max_age_hours else 1


if __name__ == "__main__":
    sys.exit(main())
