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


def _response_items(payload: object) -> list[object]:
    if isinstance(payload, dict) and isinstance(payload.get("response"), list):
        return payload["response"]
    return []


def _select_api_football_league_id(payload: object, season: int) -> str:
    rows = _response_items(payload)
    fallback = ""
    for row in rows:
        if not isinstance(row, dict):
            continue
        league = row.get("league") if isinstance(row.get("league"), dict) else {}
        league_name = str(league.get("name", ""))
        league_id = str(league.get("id", ""))
        if league_name.lower() != "world cup" or not league_id:
            continue
        fallback = fallback or league_id
        seasons = row.get("seasons") if isinstance(row.get("seasons"), list) else []
        if any(isinstance(item, dict) and item.get("year") == season for item in seasons):
            return league_id
    return fallback


def _api_manifest(response) -> dict[str, object]:
    detail: dict[str, object] = {
        "status_code": response.status_code,
        "url": response.url,
    }
    try:
        payload = response.json()
    except json.JSONDecodeError:
        return detail
    if isinstance(payload, dict):
        paging = payload.get("paging")
        errors = payload.get("errors")
        results = payload.get("results")
        if paging:
            detail["paging"] = paging
        if errors:
            detail["errors"] = errors
        if results is not None:
            detail["results"] = results
    return detail


def _write_api_response(destination: Path, filename: str, response) -> None:
    if response.ok:
        _write_json(destination / filename, response.json())


def _fixture_ids_from_payload(payload: object) -> list[str]:
    fixtures: list[tuple[str, str, str]] = []
    for row in _response_items(payload):
        if not isinstance(row, dict):
            continue
        fixture = row.get("fixture") if isinstance(row.get("fixture"), dict) else {}
        fixture_id = fixture.get("id")
        fixture_date = str(fixture.get("date", ""))
        status = fixture.get("status") if isinstance(fixture.get("status"), dict) else {}
        status_short = str(status.get("short", ""))
        if fixture_id not in (None, ""):
            fixtures.append((str(fixture_id), fixture_date, status_short))

    upcoming = [
        item
        for item in fixtures
        if item[2] in {"NS", "TBD"} or item[2] == ""
    ]
    selected = upcoming if upcoming else fixtures
    selected.sort(key=lambda item: item[1])
    return [item[0] for item in selected]


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
    parser.add_argument(
        "--api-football-advanced",
        action="store_true",
        help="Fetch API-Football injuries, odds, players, and capped fixture-level details.",
    )
    parser.add_argument(
        "--api-football-max-fixtures",
        type=int,
        default=0,
        help="Maximum API-Football fixtures to expand into lineups/events/statistics/predictions.",
    )
    parser.add_argument(
        "--api-football-max-player-pages",
        type=int,
        default=1,
        help="Maximum API-Football player-stat pages to request when advanced pulls are enabled.",
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
            manifest["sources"]["api-football"] = {
                "daily_limit_note": "Default pull is quota-light for the 100 requests/day plan."
            }

            status = client.status()
            _write_api_response(destination, "api_football_status.json", status)
            manifest["sources"]["api-football"]["status"] = _api_manifest(status)

            leagues = client.leagues(search="World Cup")
            if leagues.ok:
                _write_json(destination / "api_football_world_cup_leagues.json", leagues.json())
            manifest["sources"]["api-football"]["leagues"] = _api_manifest(leagues)

            league_id = settings.api_football_world_cup_league_id
            if leagues.ok:
                league_id = league_id or _select_api_football_league_id(
                    leagues.json(), settings.api_football_season
                )
            manifest["sources"]["api-football"]["selected_league_id"] = league_id or ""

            fixtures_payload: object = {}
            if league_id:
                fixtures = client.fixtures(
                    league=league_id,
                    season=settings.api_football_season,
                )
                if fixtures.ok:
                    fixtures_payload = fixtures.json()
                    _write_json(destination / "api_football_world_cup_fixtures.json", fixtures_payload)
                manifest["sources"]["api-football"]["fixtures"] = {
                    "status_code": fixtures.status_code,
                    "url": fixtures.url,
                }

                teams = client.teams(
                    league=league_id,
                    season=settings.api_football_season,
                )
                _write_api_response(destination, "api_football_world_cup_teams.json", teams)
                manifest["sources"]["api-football"]["teams"] = _api_manifest(teams)

                standings = client.standings(
                    league=league_id,
                    season=settings.api_football_season,
                )
                _write_api_response(destination, "api_football_world_cup_standings.json", standings)
                manifest["sources"]["api-football"]["standings"] = _api_manifest(standings)

                if args.api_football_advanced:
                    injuries = client.injuries(league=league_id, season=settings.api_football_season)
                    _write_api_response(destination, "api_football_world_cup_injuries.json", injuries)
                    manifest["sources"]["api-football"]["injuries"] = _api_manifest(injuries)

                    odds = client.odds(league=league_id, season=settings.api_football_season, page=1)
                    _write_api_response(destination, "api_football_world_cup_odds_page_1.json", odds)
                    manifest["sources"]["api-football"]["odds_page_1"] = _api_manifest(odds)

                    player_pages: dict[str, object] = {}
                    max_pages = max(0, args.api_football_max_player_pages)
                    for page in range(1, max_pages + 1):
                        players = client.players(
                            league=league_id,
                            season=settings.api_football_season,
                            page=page,
                        )
                        filename = f"api_football_world_cup_players_page_{page}.json"
                        _write_api_response(destination, filename, players)
                        player_pages[f"page_{page}"] = _api_manifest(players)
                        if not players.ok:
                            break
                        payload = players.json()
                        paging = payload.get("paging") if isinstance(payload, dict) else {}
                        if isinstance(paging, dict) and page >= int(paging.get("total", page) or page):
                            break
                    manifest["sources"]["api-football"]["players"] = player_pages

                    fixture_ids = _fixture_ids_from_payload(fixtures_payload)
                    expanded: dict[str, object] = {}
                    max_fixtures = max(0, args.api_football_max_fixtures)
                    for fixture_id in fixture_ids[:max_fixtures]:
                        expanded[fixture_id] = {}
                        detail_calls = {
                            "lineups": client.fixture_lineups(fixture_id),
                            "events": client.fixture_events(fixture_id),
                            "fixture_statistics": client.fixture_statistics(fixture_id),
                            "fixture_player_statistics": client.fixture_player_statistics(fixture_id),
                            "predictions": client.predictions(fixture_id),
                        }
                        for label, response in detail_calls.items():
                            filename = f"api_football_fixture_{fixture_id}_{label}.json"
                            _write_api_response(destination, filename, response)
                            expanded[fixture_id][label] = _api_manifest(response)
                    manifest["sources"]["api-football"]["fixture_detail"] = expanded

    _write_json(destination / "manifest.json", manifest)
    print(f"Wrote raw snapshot to {destination}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
