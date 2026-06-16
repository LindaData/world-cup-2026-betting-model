from __future__ import annotations

import argparse
import csv
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from wc_model.config import load_settings  # noqa: E402
from wc_model.providers.open_meteo import OpenMeteoClient  # noqa: E402


COUNTRY_NAMES = {"United States": "US", "USA": "US", "Canada": "CA", "Mexico": "MX"}
CITY_TO_VENUE_HINT = {
    "Mexico City": "mexico_city_estadio_azteca",
    "Zapopan": "guadalajara_estadio_akron",
    "Guadalupe": "monterrey_estadio_bbva",
    "Toronto": "toronto_bmo_field",
    "Inglewood": "los_angeles_sofi_stadium",
    "Santa Clara": "sf_bay_area_levis_stadium",
    "East Rutherford": "new_york_new_jersey_metlife_stadium",
    "Foxborough": "boston_gillette_stadium",
    "Arlington": "dallas_att_stadium",
    "Houston": "houston_nrg_stadium",
    "Atlanta": "atlanta_mercedes_benz_stadium",
    "Miami Gardens": "miami_hard_rock_stadium",
    "Kansas City": "kansas_city_arrowhead_stadium",
    "Philadelphia": "philadelphia_lincoln_financial_field",
    "Seattle": "seattle_lumen_field",
    "Vancouver": "vancouver_bc_place",
}


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def write_csv(path: Path, rows: list[dict[str, object]], fieldnames: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")


def venue_lookup() -> dict[str, dict[str, str]]:
    venues = read_csv(ROOT / "data" / "seed" / "venues_2026_world_cup.csv")
    by_id = {venue["venue_id"]: venue for venue in venues}
    return by_id


def fixture_venue(fixture: dict[str, str], venues: dict[str, dict[str, str]]) -> dict[str, str] | None:
    hinted = CITY_TO_VENUE_HINT.get(fixture.get("city", ""))
    if hinted and hinted in venues:
        return venues[hinted]

    fixture_country = COUNTRY_NAMES.get(fixture.get("country", ""), fixture.get("country", ""))
    for venue in venues.values():
        if venue.get("country") != fixture_country:
            continue
        if fixture.get("city", "") and fixture["city"] in venue.get("city", ""):
            return venue
    return None


def hourly_rows(fixture: dict[str, str], venue: dict[str, str], response_payload: dict[str, Any]) -> list[dict[str, object]]:
    hourly = response_payload.get("hourly", {})
    times = hourly.get("time", [])
    rows: list[dict[str, object]] = []
    for index, weather_time in enumerate(times):
        rows.append(
            {
                "source_match_id": fixture.get("source_match_id", ""),
                "fixture_date": fixture.get("date", ""),
                "home_team": fixture.get("home_team", ""),
                "away_team": fixture.get("away_team", ""),
                "venue_id": venue.get("venue_id", ""),
                "venue_name": venue.get("venue_name", ""),
                "city": fixture.get("city", ""),
                "country": fixture.get("country", ""),
                "weather_time": weather_time,
                "temperature_2m": hourly.get("temperature_2m", [None] * len(times))[index],
                "relative_humidity_2m": hourly.get("relative_humidity_2m", [None] * len(times))[index],
                "precipitation": hourly.get("precipitation", [None] * len(times))[index],
                "wind_speed_10m": hourly.get("wind_speed_10m", [None] * len(times))[index],
            }
        )
    return rows


def main() -> int:
    parser = argparse.ArgumentParser(description="Fetch weather context for World Cup fixture venues.")
    parser.add_argument("--max-fixtures", type=int, default=None)
    args = parser.parse_args()

    settings = load_settings()
    client = OpenMeteoClient()
    fixtures = read_csv(ROOT / "data" / "processed" / "public_csv" / "fact_2026_world_cup_fixtures.csv")
    if args.max_fixtures:
        fixtures = fixtures[: args.max_fixtures]

    venues = venue_lookup()
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    raw_dir = settings.root / "data" / "raw" / "weather" / stamp
    processed_dir = settings.root / "data" / "processed" / "public_csv"

    rows: list[dict[str, object]] = []
    manifest: dict[str, Any] = {"pulled_at_utc": datetime.now(timezone.utc).isoformat(), "fixtures": []}

    for fixture in fixtures:
        venue = fixture_venue(fixture, venues)
        if venue is None:
            manifest["fixtures"].append({"source_match_id": fixture.get("source_match_id"), "status": "venue_not_mapped"})
            continue
        response = client.archive_hourly(
            latitude=float(venue["latitude"]),
            longitude=float(venue["longitude"]),
            start_date=fixture["date"],
            end_date=fixture["date"],
            timezone=venue["timezone"],
        )
        key = f"weather_{fixture.get('source_match_id')}.json"
        manifest["fixtures"].append(
            {
                "source_match_id": fixture.get("source_match_id"),
                "status_code": response.status_code,
                "url": response.url,
                "venue_id": venue["venue_id"],
            }
        )
        write_json(raw_dir / key, response.json() if response.ok else {"error": response.text})
        if response.ok:
            rows.extend(hourly_rows(fixture, venue, response.json()))

    write_json(raw_dir / "manifest.json", manifest)
    write_csv(
        processed_dir / "fact_fixture_weather_hourly_open_meteo.csv",
        rows,
        [
            "source_match_id",
            "fixture_date",
            "home_team",
            "away_team",
            "venue_id",
            "venue_name",
            "city",
            "country",
            "weather_time",
            "temperature_2m",
            "relative_humidity_2m",
            "precipitation",
            "wind_speed_10m",
        ],
    )
    print(f"Wrote {len(rows)} hourly weather rows")
    print(f"Raw weather snapshot: {raw_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

