from __future__ import annotations

import json
import os
import re
from typing import Any

import publish_sports_data as base


def season_sort_key(value: str) -> tuple[int, str]:
    match = re.search(r"(19|20)\d{2}", value)
    return (int(match.group(0)) if match else -1, value)


def candidate_seasons(league: dict[str, Any], sport: str, now: Any) -> list[str]:
    requested = base.desired_season(sport, now)
    available = base.season_values(league.get("seasons", []))
    generated: list[str] = []
    if sport == "basketball":
        start = now.year if now.month >= 9 else now.year - 1
        generated = [f"{year}-{year + 1}" for year in range(start, start - 8, -1)]
    else:
        generated = [str(year) for year in range(now.year, now.year - 8, -1)]
    ordered = [requested] + sorted(available, key=season_sort_key, reverse=True) + generated
    return list(dict.fromkeys(str(value) for value in ordered if value))


def main() -> int:
    api_key = os.environ.get("API_SPORTS_KEY", "").strip()
    if not api_key:
        raise SystemExit("API_SPORTS_KEY is not set")

    now = base.utc_now()
    raw_dir = base.RAW_ROOT / now.strftime("%Y%m%dT%H%M%SZ")
    raw_dir.mkdir(parents=True, exist_ok=False)
    base.DATA_DIR.mkdir(parents=True, exist_ok=True)
    snapshots: dict[str, dict[str, Any]] = {}
    quota_headers: dict[str, Any] = {}

    for sport, cfg in base.SPORTS.items():
        leagues_payload, headers = base.request_json(cfg["host"], "/leagues", api_key)
        quota_headers[sport] = headers
        league = base.choose_league(base.response_items(leagues_payload), cfg["league_name"], cfg["country"])
        league_id = league.get("id")
        if league_id in (None, ""):
            raise RuntimeError(f"Resolved {sport} league has no ID")

        games_payload: dict[str, Any] | None = None
        standings_payload: dict[str, Any] | None = None
        selected_season = ""
        attempts: list[dict[str, str]] = []

        for season in candidate_seasons(league, sport, now):
            try:
                games_payload, headers = base.request_json(
                    cfg["host"], "/games", api_key, {"league": league_id, "season": season}
                )
                standings_payload, headers = base.request_json(
                    cfg["host"], "/standings", api_key, {"league": league_id, "season": season}
                )
                selected_season = season
                quota_headers[sport] = headers
                attempts.append({"season": season, "status": "selected"})
                break
            except RuntimeError as exc:
                message = str(exc)
                attempts.append({"season": season, "status": message[:240]})
                lowered = message.lower()
                if "plan" in lowered or "season" in lowered or "access" in lowered:
                    continue
                raise

        if games_payload is None or standings_payload is None or not selected_season:
            raise RuntimeError(f"No accessible {sport} season found. Attempts: {attempts}")

        (raw_dir / f"{sport}_leagues.json").write_text(json.dumps(leagues_payload, indent=2), encoding="utf-8")
        (raw_dir / f"{sport}_games.json").write_text(json.dumps(games_payload, indent=2), encoding="utf-8")
        (raw_dir / f"{sport}_standings.json").write_text(json.dumps(standings_payload, indent=2), encoding="utf-8")
        (raw_dir / f"{sport}_season_attempts.json").write_text(json.dumps(attempts, indent=2), encoding="utf-8")

        all_games = [
            base.game_row(sport, item)
            for item in base.response_items(games_payload)
            if isinstance(item, dict)
        ]
        games = base.publish_window(all_games, now)
        standings = [
            base.standings_row(sport, item)
            for item in base.flatten_standings(standings_payload.get("response", []))
        ]

        game_fields = [
            "sport", "game_id", "date_utc", "status", "league_id", "league", "season",
            "home_team_id", "home_team", "away_team_id", "away_team", "home_score", "away_score",
        ]
        standing_fields = [
            "sport", "position", "group", "team_id", "team", "played", "wins", "losses",
            "percentage", "form",
        ]
        base.write_csv(base.DATA_DIR / f"{sport}_games.csv", games, game_fields)
        base.write_csv(base.DATA_DIR / f"{sport}_standings.csv", standings, standing_fields)

        snapshot = {
            "sport": sport,
            "refreshed_at_utc": now.isoformat().replace("+00:00", "Z"),
            "league_id": league_id,
            "league_name": league.get("name", cfg["league_name"]),
            "season": selected_season,
            "season_selection_attempts": attempts,
            "games": games,
            "standings": standings,
        }
        snapshots[sport] = snapshot
        (base.DATA_DIR / f"{sport}_snapshot.json").write_text(
            json.dumps(snapshot, indent=2), encoding="utf-8"
        )

    refreshed = now.isoformat().replace("+00:00", "Z")
    manifest = {
        "refreshed_at_utc": refreshed,
        "sports": {
            key: {
                "league_id": value["league_id"],
                "season": value["season"],
                "published_games": len(value["games"]),
                "standings_rows": len(value["standings"]),
            }
            for key, value in snapshots.items()
        },
        "quota_headers": quota_headers,
        "raw_artifact_directory": str(raw_dir.relative_to(base.ROOT)),
    }
    (base.DATA_DIR / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    (base.DOCS_DIR / "index.html").write_text(
        base.render_site(snapshots, refreshed), encoding="utf-8"
    )
    print(json.dumps(manifest, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
