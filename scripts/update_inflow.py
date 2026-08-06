#!/usr/bin/env python3
"""
Update the water-year inflow dataset used by the Powell Mass-Balance calculator.

Usage:
    python3 scripts/update_inflow.py --year 2026 --acre-feet 4500000
    python3 scripts/update_inflow.py --year 2026 --acre-feet 4500000 --source "https://example.com/forecast"

This safely reads data/historical_inflow.json, updates (or adds) a single
water-year value, refreshes the "last_updated" date, and writes the file back
out with the same formatting/order. It is intentionally simple and dependency
free (standard library only) so it can run in GitHub Actions without an
install step.
"""
import argparse
import datetime
import json
import pathlib
import sys

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
DATA_FILE = REPO_ROOT / "data" / "historical_inflow.json"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--year", type=int, required=True, help="Water year to update, e.g. 2026")
    parser.add_argument(
        "--acre-feet",
        type=float,
        required=True,
        help="Unregulated inflow volume for the water year, in acre-feet (whole AF, e.g. 4500000)",
    )
    parser.add_argument(
        "--source",
        default=None,
        help="Optional URL describing where this value came from (stored in the JSON's 'source' field)",
    )
    parser.add_argument(
        "--file",
        default=str(DATA_FILE),
        help=f"Path to historical_inflow.json (default: {DATA_FILE})",
    )
    args = parser.parse_args()

    data_path = pathlib.Path(args.file)
    if not data_path.exists():
        print(f"ERROR: data file not found: {data_path}", file=sys.stderr)
        return 1

    with data_path.open("r", encoding="utf-8") as f:
        payload = json.load(f)

    if "years" not in payload or not isinstance(payload["years"], dict):
        print("ERROR: unexpected JSON shape -- missing top-level 'years' object", file=sys.stderr)
        return 1

    year_key = str(args.year)
    af_value = round(args.acre_feet)
    old_value = payload["years"].get(year_key)

    payload["years"][year_key] = af_value
    # Keep years sorted numerically for readability.
    payload["years"] = {k: payload["years"][k] for k in sorted(payload["years"], key=int)}
    payload["last_updated"] = datetime.date.today().isoformat()
    if args.source:
        payload["source"] = args.source

    with data_path.open("w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2)
        f.write("\n")

    if old_value is None:
        print(f"Added WY{args.year} = {af_value:,} AF")
    else:
        print(f"Updated WY{args.year}: {old_value:,} AF -> {af_value:,} AF")
    print(f"last_updated set to {payload['last_updated']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
