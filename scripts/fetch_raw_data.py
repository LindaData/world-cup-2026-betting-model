from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from wc_model.config import load_settings  # noqa: E402
from wc_model.http import HttpClient  # noqa: E402
from wc_model.providers.api_football import ApiFootballClient  # noqa: E402
from wc_model.providers.football_data import FootballDataClient  # noqa: E402
from wc_model.providers.public_files import download_public_sources  # noqa: E402
from wc_model.providers.the_odds_api import TheOddsApiClient  # noqa: E402
from wc_model.providers.wikimedia import download_wikimedia_pages  # noqa: E402


def _timestamp_dir(root: Path) -> Path:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    path = root / "data" / "raw" / stamp
    path.mkdir(parents=True, exist_ok=False)
    return path


def _write_json(path: Path, payload: object) -> None:
    path.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Fetch raw World Cup model data.")
    parser.add_argument(
        "--sources",
        nargs="+",
        default=["public"],
        choices=["public", "wikimedia", "official-fifa", "football-data", "odds", "api-football"],
        help="Sources to pull. Defaults to public files only.",
    )
    parser.add_argument(
        "--include-quota-odds",
        action="store_true",
        help="Fetch odds data. This can consume Odds API quota.",
    )
    args = parser.parse_args()

    settings = load_settings()
    destination = _timestamp_dir(settings.root)
    manifest: dict[str, object] = {"destination": str(destination), "sources": {}}

    if "public" in args.sources:
        responses = download_public_sources(settings, destination)
        manifest["sources"]["public"] = {
            filename: {"status_code": response.status_code, "url": response.url}
            for filename, response in responses.items()
        }

    if "wikimedia" in args.sources:
        responses = download_wikimedia_pages(settings, destination)
        manifest["sources"]["wikimedia"] = {
            filename: {"status_code": response.status_code, "url": response.url}
            for filename, response in responses.items()
        }

    if "official-fifa" in args.sources:
        client = HttpClient()
        response = client.download_bytes(
            settings.fifa_2026_squad_pdf_url,
            destination / "fifa_2026_squad_list.pdf",
        )
        manifest["sources"]["official-fifa"] = {
            "fifa_2026_squad_list.pdf": {
                "status_code": response.status_code,
                "url": response.url,
                "detail": response.text,
            }
        }

    if "football-data" in args.sources:
        if not settings.football_data_token:
            manifest["sources"]["football-data"] = {"skipped": "FOOTBALL_DATA_TOKEN is not set"}
        else:
            client = FootballDataClient(settings.football_data_token)
            pulls = {
                "football_data_world_cup_matches.json": client.competition_matches(
                    settings.football_data_world_cup_competition, settings.football_data_season
                ),
                "football_data_world_cup_teams.json": client.competition_teams(
                    settings.football_data_world_cup_competition, settings.football_data_season
                ),
                "football_data_world_cup_standings.json": client.competition_standings(
                    settings.football_data_world_cup_competition, settings.football_data_season
                ),
            }
            manifest["sources"]["football-data"] = {}
            for filename, response in pulls.items():
                if response.ok:
                    _write_json(destination / filename, response.json())
                manifest["sources"]["football-data"][filename] = {
                    "status_code": response.status_code,
                    "url": response.url,
                }

    if "odds" in args.sources:
        if not settings.odds_api_key:
            manifest["sources"]["odds"] = {"skipped": "THE_ODDS_API_KEY is not set"}
        else:
            client = TheOddsApiClient(settings.odds_api_key)
            sports = client.sports()
            if sports.ok:
                _write_json(destination / "odds_api_sports.json", sports.json())
            manifest["sources"]["odds"] = {
                "sports": {"status_code": sports.status_code, "url": sports.url}
            }

            if args.include_quota_odds:
                odds = client.odds(
                    sport=settings.odds_api_sport_key,
                    regions=settings.odds_regions,
                    markets=settings.odds_markets,
                    odds_format=settings.odds_format,
                )
                if odds.ok:
                    _write_json(destination / "odds_api_world_cup_odds.json", odds.json())
                manifest["sources"]["odds"]["odds"] = {
                    "status_code": odds.status_code,
                    "url": odds.url,
                }

    if "api-football" in args.sources:
        if not settings.api_football_key:
            manifest["sources"]["api-football"] = {"skipped": "API_FOOTBALL_KEY is not set"}
        else:
            client = ApiFootballClient(settings.api_football_key, host=settings.api_football_host)
            leagues = client.leagues(search="World Cup")
            if leagues.ok:
                _write_json(destination / "api_football_world_cup_leagues.json", leagues.json())
            manifest["sources"]["api-football"] = {
                "leagues": {"status_code": leagues.status_code, "url": leagues.url}
            }

            if settings.api_football_world_cup_league_id:
                fixtures = client.fixtures(
                    league=settings.api_football_world_cup_league_id,
                    season=settings.api_football_season,
                )
                if fixtures.ok:
                    _write_json(destination / "api_football_world_cup_fixtures.json", fixtures.json())
                manifest["sources"]["api-football"]["fixtures"] = {
                    "status_code": fixtures.status_code,
                    "url": fixtures.url,
                }

                odds = client.odds(
                    league=settings.api_football_world_cup_league_id,
                    season=settings.api_football_season,
                )
                if odds.ok:
                    _write_json(destination / "api_football_world_cup_odds.json", odds.json())
                manifest["sources"]["api-football"]["odds"] = {
                    "status_code": odds.status_code,
                    "url": odds.url,
                }

    _write_json(destination / "manifest.json", manifest)
    print(f"Wrote raw snapshot to {destination}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
