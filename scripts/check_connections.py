from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from wc_model.config import load_settings  # noqa: E402
from wc_model.http import HttpClient  # noqa: E402
from wc_model.providers.api_football import ApiFootballClient  # noqa: E402
from wc_model.providers.football_data import FootballDataClient  # noqa: E402
from wc_model.providers.open_meteo import OpenMeteoClient  # noqa: E402
from wc_model.providers.the_odds_api import TheOddsApiClient  # noqa: E402


def _short_status(name: str, status_code: int, detail: str = "") -> None:
    suffix = f" - {detail}" if detail else ""
    print(f"{name}: HTTP {status_code}{suffix}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Check configured data-source connections.")
    parser.add_argument(
        "--include-quota-odds",
        action="store_true",
        help="Also call the odds endpoint. This can consume Odds API quota.",
    )
    args = parser.parse_args()

    settings = load_settings()

    public = HttpClient()
    response = public.get(settings.openfootball_cup_url)
    _short_status("openfootball cup", response.status_code, f"{len(response.text)} chars")

    response = public.get(settings.international_results_url)
    first_line = response.text.splitlines()[0] if response.text else ""
    _short_status("international results", response.status_code, first_line)

    weather = OpenMeteoClient()
    response = weather.forecast_hourly(
        latitude=40.8135,
        longitude=-74.0744,
        start_date="2026-06-16",
        end_date="2026-06-16",
        timezone="America/New_York",
    )
    _short_status("open-meteo forecast sample", response.status_code)

    if settings.football_data_token:
        client = FootballDataClient(settings.football_data_token)
        response = client.competition_matches(
            competition=settings.football_data_world_cup_competition,
            season=settings.football_data_season,
        )
        detail = ""
        if response.ok:
            payload = response.json()
            detail = f"{payload.get('count', 'unknown')} matches"
        _short_status("football-data world cup matches", response.status_code, detail)
    else:
        print("football-data: skipped, FOOTBALL_DATA_TOKEN is not set")

    if settings.odds_api_key:
        client = TheOddsApiClient(settings.odds_api_key)
        response = client.sports()
        detail = ""
        if response.ok:
            candidates = client.discover_world_cup_sports(response.json())
            keys = ", ".join(sport["key"] for sport in candidates[:5])
            detail = f"world cup candidates: {keys or 'none found'}"
        _short_status("the-odds-api sports", response.status_code, detail)

        if args.include_quota_odds:
            response = client.odds(
                sport=settings.odds_api_sport_key,
                regions=settings.odds_regions,
                markets=settings.odds_markets,
                odds_format=settings.odds_format,
            )
            _short_status("the-odds-api odds", response.status_code)
    else:
        print("the-odds-api: skipped, THE_ODDS_API_KEY is not set")

    if settings.api_football_key:
        client = ApiFootballClient(settings.api_football_key, host=settings.api_football_host)
        response = client.leagues(search="World Cup")
        _short_status("api-football leagues search", response.status_code)
    else:
        print("api-football: skipped, API_FOOTBALL_KEY is not set")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

