from __future__ import annotations

import json
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs" / "sports-data" / "data"

SPORTS = {
    "nba": "https://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard",
    "mlb": "https://site.api.espn.com/apis/site/v2/sports/baseball/mlb/scoreboard",
    "football": "https://site.api.espn.com/apis/site/v2/sports/soccer/fifa.world/scoreboard",
    "nfl": "https://site.api.espn.com/apis/site/v2/sports/football/nfl/scoreboard",
    "nhl": "https://site.api.espn.com/apis/site/v2/sports/hockey/nhl/scoreboard",
    "cfb": "https://site.api.espn.com/apis/site/v2/sports/football/college-football/scoreboard",
}


def fetch_json(url: str) -> dict:
    request = Request(url, headers={"User-Agent": "LindaData-Sports-Hub/1.0", "Accept": "application/json"})
    try:
        with urlopen(request, timeout=30) as response:
            return json.loads(response.read().decode("utf-8"))
    except (HTTPError, URLError, TimeoutError, json.JSONDecodeError) as exc:
        raise RuntimeError(f"Could not fetch {url}: {exc}") from exc


def normalize_event(sport: str, event: dict) -> dict:
    competition = (event.get("competitions") or [{}])[0]
    competitors = competition.get("competitors") or []
    home = next((x for x in competitors if x.get("homeAway") == "home"), {})
    away = next((x for x in competitors if x.get("homeAway") == "away"), {})
    status = event.get("status") or {}
    status_type = status.get("type") or {}

    def team_name(item: dict) -> str:
        team = item.get("team") or {}
        return team.get("displayName") or team.get("shortDisplayName") or team.get("name") or ""

    return {
        "sport": sport,
        "event_id": event.get("id", ""),
        "date_utc": event.get("date", ""),
        "name": event.get("name", ""),
        "short_name": event.get("shortName", ""),
        "status": status_type.get("description") or status_type.get("detail") or "",
        "status_short": status_type.get("shortDetail") or status_type.get("state") or "",
        "state": status_type.get("state", ""),
        "period": status.get("period", ""),
        "clock": status.get("displayClock", ""),
        "home_team": team_name(home),
        "away_team": team_name(away),
        "home_score": home.get("score", ""),
        "away_score": away.get("score", ""),
        "home_record": ((home.get("records") or [{}])[0]).get("summary", ""),
        "away_record": ((away.get("records") or [{}])[0]).get("summary", ""),
        "venue": ((competition.get("venue") or {}).get("fullName", "")),
        "broadcasts": [name for item in competition.get("broadcasts") or [] for name in item.get("names") or []],
        "link": next((link.get("href") for link in event.get("links") or [] if link.get("href")), ""),
    }


def main() -> int:
    now = datetime.now(timezone.utc)
    dates = [(now + timedelta(days=offset)).strftime("%Y%m%d") for offset in (-1, 0, 1)]
    OUT.mkdir(parents=True, exist_ok=True)
    manifest = {"refreshed_at_utc": now.isoformat().replace("+00:00", "Z"), "feeds": {}}

    for sport, base_url in SPORTS.items():
        events_by_id: dict[str, dict] = {}
        errors: list[str] = []
        for date in dates:
            try:
                payload = fetch_json(f"{base_url}?dates={date}&limit=100")
                for event in payload.get("events") or []:
                    normalized = normalize_event(sport, event)
                    events_by_id[str(normalized["event_id"])] = normalized
            except RuntimeError as exc:
                errors.append(str(exc))

        events = sorted(events_by_id.values(), key=lambda item: item.get("date_utc", ""))
        output = {
            "sport": sport,
            "refreshed_at_utc": manifest["refreshed_at_utc"],
            "dates_requested": dates,
            "event_count": len(events),
            "events": events,
            "errors": errors,
        }
        (OUT / f"{sport}_live.json").write_text(json.dumps(output, indent=2), encoding="utf-8")
        manifest["feeds"][sport] = {"event_count": len(events), "errors": len(errors)}

    (OUT / "live_manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(json.dumps(manifest, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
