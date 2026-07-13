"""Offline tests for publish_multisport_espn.py normalizers.

Feeds synthetic ESPN-shaped scoreboard and standings payloads (mirroring the
structures consumed by publish_football_espn.py / fetch_live_scoreboards.py
and the committed docs/sports-data/data/*_live.json snapshots) through the
normalizers and asserts the published schemas. No network access needed.

Run: python scripts/test_publish_multisport_espn.py
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from publish_multisport_espn import (  # noqa: E402
    SPORTS,
    normalize_event,
    normalize_standings,
    payload_league_name,
    payload_season,
)

NFL = next(s for s in SPORTS if s["key"] == "nfl")
NBA = next(s for s in SPORTS if s["key"] == "nba")

SCHEDULE_FIELDS = [
    "sport", "game_id", "date_utc", "status", "status_code", "league_id",
    "league", "season", "home_team_id", "home_team", "away_team_id",
    "away_team", "home_score", "away_score", "venue", "city",
]
STANDINGS_FIELDS = [
    "sport", "position", "group", "team_id", "team", "played", "wins",
    "losses", "percentage", "form",
]

SCOREBOARD_PAYLOAD = {
    "leagues": [{"name": "National Football League", "abbreviation": "NFL", "season": {"year": 2026}}],
    "season": {"type": 2, "year": 2026},
    "events": [
        {  # completed game
            "id": "401671234",
            "date": "2026-09-10T00:20Z",
            "season": {"year": 2026, "type": 2},
            "status": {"type": {"state": "post", "completed": True, "description": "Final", "detail": "Final"}},
            "competitions": [{
                "venue": {"fullName": "Arrowhead Stadium", "address": {"city": "Kansas City", "state": "MO"}},
                "competitors": [
                    {"homeAway": "home", "score": "27",
                     "team": {"id": "12", "displayName": "Kansas City Chiefs"}},
                    {"homeAway": "away", "score": "20",
                     "team": {"id": "33", "displayName": "Baltimore Ravens"}},
                ],
            }],
        },
        {  # pre-game: placeholder "0" scores must become null
            "id": "401675678",
            "date": "2026-09-14T17:00Z",
            "status": {"type": {"state": "pre", "completed": False, "description": "Scheduled"}},
            "competitions": [{
                "venue": {"fullName": "Lambeau Field", "address": {"city": "Green Bay"}},
                "competitors": [
                    {"homeAway": "home", "score": "0", "team": {"id": "9", "displayName": "Green Bay Packers"}},
                    {"homeAway": "away", "score": "0", "team": {"id": "8", "displayName": "Detroit Lions"}},
                ],
            }],
        },
        {  # pathological: empty competitions, missing status — must not crash
            "id": "401679999",
            "date": "2026-09-15T00:15Z",
            "competitions": [],
        },
    ],
}

# apis/v2 standings shape: children = conferences, optionally nested divisions.
STANDINGS_PAYLOAD = {
    "name": "National Basketball Association",
    "children": [
        {
            "name": "Eastern Conference",
            "standings": {"entries": [
                {
                    "team": {"id": "2", "displayName": "Boston Celtics"},
                    "stats": [
                        {"name": "wins", "value": 61},
                        {"name": "losses", "value": 21},
                        {"name": "winPercent", "value": 0.744},
                        {"name": "gamesPlayed", "value": 82},
                        {"name": "streak", "value": 3, "displayValue": "W3"},
                        {"name": "playoffSeat", "value": 1},
                    ],
                },
                {  # sparse stats: no gamesPlayed / winPercent / rank -> fallbacks
                    "team": {"id": "20", "displayName": "Philadelphia 76ers"},
                    "stats": [
                        {"name": "wins", "value": 40},
                        {"name": "losses", "value": 42},
                        {"name": "streak", "value": -2},
                    ],
                },
            ]},
        },
        {  # conference wrapping division children (NFL-style nesting)
            "name": "Western Conference",
            "children": [{
                "name": "Pacific Division",
                "standings": {"entries": [
                    {"team": {"id": "13", "displayName": "Los Angeles Lakers"}, "stats": []},
                ]},
            }],
        },
    ],
}

FLAT_STANDINGS_PAYLOAD = {  # single ungrouped table directly under "standings"
    "standings": {"entries": [
        {"team": {"id": "1", "displayName": "Some Team"},
         "stats": [{"name": "wins", "value": 5}, {"name": "losses", "value": 5}]},
    ]},
}


def check(label: str, condition: bool) -> None:
    print(f"  {'ok' if condition else 'FAIL'}: {label}")
    if not condition:
        raise AssertionError(label)


def main() -> int:
    print("schedule normalizer")
    season = payload_season(SCOREBOARD_PAYLOAD)
    league = payload_league_name(SCOREBOARD_PAYLOAD, NFL["label"])
    rows = [normalize_event(NFL, event, season, league) for event in SCOREBOARD_PAYLOAD["events"]]
    check("season extracted from payload", season == "2026")
    check("league name from payload", league == "National Football League")
    for row in rows:
        check(f"row {row['game_id'] or '<empty>'} has exact GameRow fields", list(row) == SCHEDULE_FIELDS)
    final, pre, broken = rows
    check("final: status_code FT", final["status_code"] == "FT")
    check("final: int scores", final["home_score"] == 27 and final["away_score"] == 20)
    check("final: teams + ids", final["home_team"] == "Kansas City Chiefs" and final["away_team_id"] == "33")
    check("final: venue/city", final["venue"] == "Arrowhead Stadium" and final["city"] == "Kansas City")
    check("final: no draw fields", "draws" not in final and "halftime_home" not in final)
    check("pre: scores are null", pre["home_score"] is None and pre["away_score"] is None)
    check("pre: status_code is state", pre["status_code"] == "pre")
    check("broken event survives with nulls", broken["home_team"] == "" and broken["home_score"] is None)

    print("standings normalizer")
    standings = normalize_standings(NBA, STANDINGS_PAYLOAD)
    check("three rows across nested groups", len(standings) == 3)
    for row in standings:
        check(f"{row['team'] or '<empty>'} has exact StandingRow fields", list(row) == STANDINGS_FIELDS)
    by_team = {row["team"]: row for row in standings}
    celtics = by_team["Boston Celtics"]
    check("full stats parsed", celtics["wins"] == 61 and celtics["losses"] == 21 and celtics["played"] == 82)
    check("winPercent used", celtics["percentage"] == 0.744)
    check("streak displayValue as form", celtics["form"] == "W3")
    check("position from playoffSeat", celtics["position"] == 1)
    check("group is conference name", celtics["group"] == "Eastern Conference")
    sixers = by_team["Philadelphia 76ers"]
    check("played derived from W+L", sixers["played"] == 82)
    check("percentage derived from W/GP", abs(sixers["percentage"] - 40 / 82) < 1e-9)
    check("numeric streak formatted", sixers["form"] == "L2")
    check("position falls back to order", sixers["position"] == 2)
    lakers = by_team["Los Angeles Lakers"]
    check("empty stats -> nulls, no crash",
          lakers["wins"] is None and lakers["percentage"] is None and lakers["form"] is None)
    check("nested division group name", lakers["group"] == "Western Conference - Pacific Division")

    flat = normalize_standings(NBA, FLAT_STANDINGS_PAYLOAD)
    check("flat payload -> Overall group", len(flat) == 1 and flat[0]["group"] == "Overall")
    check("empty payload -> empty list", normalize_standings(NBA, {}) == [])

    print("all checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
