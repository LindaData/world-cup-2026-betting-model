from __future__ import annotations

import csv
import html
import json
import os
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Iterable
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
DOCS_DIR = ROOT / "docs" / "sports-data"
DATA_DIR = DOCS_DIR / "data"
RAW_ROOT = ROOT / "data" / "raw" / "api_sports_publish"

SPORTS = {
    "basketball": {
        "label": "NBA Basketball",
        "host": "v1.basketball.api-sports.io",
        "league_name": "NBA",
        "country": "USA",
    },
    "baseball": {
        "label": "MLB Baseball",
        "host": "v1.baseball.api-sports.io",
        "league_name": "MLB",
        "country": "USA",
    },
}


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def request_json(host: str, path: str, api_key: str, params: dict[str, Any] | None = None) -> tuple[dict[str, Any], dict[str, str]]:
    query = urlencode(params or {}, doseq=True)
    url = f"https://{host}{path}" + (f"?{query}" if query else "")
    request = Request(
        url,
        headers={
            "x-apisports-key": api_key,
            "Accept": "application/json",
            "User-Agent": "LindaData-GitHub-Actions/1.0",
        },
    )
    for attempt in range(5):
        try:
            with urlopen(request, timeout=90) as response:
                payload = json.loads(response.read().decode("utf-8"))
                headers = {
                    key.lower(): value
                    for key, value in response.headers.items()
                    if key.lower().startswith("x-ratelimit")
                }
                if not isinstance(payload, dict):
                    raise RuntimeError("API response was not a JSON object")
                errors = payload.get("errors")
                if errors not in (None, {}, []):
                    raise RuntimeError(f"API returned errors for {path}: {errors}")
                return payload, headers
        except HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")
            if (exc.code == 429 or 500 <= exc.code < 600) and attempt < 4:
                time.sleep(min(2**attempt, 30))
                continue
            raise RuntimeError(f"HTTP {exc.code} for {path}: {body[:1000]}") from exc
        except (URLError, TimeoutError) as exc:
            if attempt < 4:
                time.sleep(min(2**attempt, 30))
                continue
            raise RuntimeError(f"Network failure for {path}: {exc}") from exc
    raise RuntimeError(f"Request failed for {path}")


def response_items(payload: dict[str, Any]) -> list[Any]:
    response = payload.get("response", [])
    if isinstance(response, list):
        return response
    if isinstance(response, dict):
        return [response]
    return []


def nested_get(value: Any, *keys: str, default: Any = None) -> Any:
    current = value
    for key in keys:
        if not isinstance(current, dict):
            return default
        current = current.get(key)
    return default if current is None else current


def normalize_text(value: Any) -> str:
    return " ".join(str(value or "").lower().replace("-", " ").split())


def choose_league(items: list[Any], league_name: str, country: str) -> dict[str, Any]:
    candidates = [item for item in items if isinstance(item, dict)]
    exact = [item for item in candidates if normalize_text(item.get("name")) == normalize_text(league_name)]
    country_exact = [
        item
        for item in exact
        if normalize_text(nested_get(item, "country", "name")) == normalize_text(country)
        or normalize_text(item.get("country")) == normalize_text(country)
    ]
    selected = (country_exact or exact or candidates)
    if not selected:
        raise RuntimeError(f"Could not resolve league {league_name}")
    return selected[0]


def season_values(value: Any) -> list[str]:
    found: list[str] = []
    if isinstance(value, (str, int, float)):
        found.append(str(value).removesuffix(".0"))
    elif isinstance(value, list):
        for item in value:
            found.extend(season_values(item))
    elif isinstance(value, dict):
        if "season" in value:
            found.extend(season_values(value["season"]))
        elif "year" in value:
            found.extend(season_values(value["year"]))
        else:
            for item in value.values():
                found.extend(season_values(item))
    return list(dict.fromkeys(found))


def desired_season(sport: str, now: datetime) -> str:
    env_name = f"{sport.upper()}_SEASON"
    configured = os.environ.get(env_name, "").strip()
    if configured:
        return configured
    if sport == "basketball":
        start = now.year if now.month >= 9 else now.year - 1
        return f"{start}-{start + 1}"
    return str(now.year)


def select_season(league: dict[str, Any], sport: str, now: datetime) -> str:
    requested = desired_season(sport, now)
    available = season_values(league.get("seasons", []))
    if not available or requested in available:
        return requested
    return sorted(available)[-1]


def parse_game_time(game: dict[str, Any]) -> datetime | None:
    timestamp = game.get("timestamp")
    if isinstance(timestamp, (int, float)):
        return datetime.fromtimestamp(timestamp, tz=timezone.utc)
    raw = game.get("date")
    if not raw:
        return None
    text = str(raw).replace("Z", "+00:00")
    try:
        parsed = datetime.fromisoformat(text)
        return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)
    except ValueError:
        try:
            return datetime.strptime(text[:10], "%Y-%m-%d").replace(tzinfo=timezone.utc)
        except ValueError:
            return None


def score_total(value: Any) -> Any:
    if isinstance(value, (int, float, str)) and value not in ("", None):
        return value
    if isinstance(value, dict):
        for key in ("total", "points", "score", "runs", "current"):
            if value.get(key) not in (None, ""):
                return value[key]
    return ""


def game_row(sport: str, game: dict[str, Any]) -> dict[str, Any]:
    dt = parse_game_time(game)
    status = game.get("status") if isinstance(game.get("status"), dict) else {}
    teams = game.get("teams") if isinstance(game.get("teams"), dict) else {}
    scores = game.get("scores") if isinstance(game.get("scores"), dict) else {}
    league = game.get("league") if isinstance(game.get("league"), dict) else {}
    home = teams.get("home") if isinstance(teams.get("home"), dict) else {}
    away = teams.get("away") if isinstance(teams.get("away"), dict) else {}
    return {
        "sport": sport,
        "game_id": game.get("id", ""),
        "date_utc": dt.isoformat().replace("+00:00", "Z") if dt else str(game.get("date", "")),
        "status": status.get("short") or status.get("long") or "",
        "league_id": league.get("id", ""),
        "league": league.get("name", ""),
        "season": league.get("season", ""),
        "home_team_id": home.get("id", ""),
        "home_team": home.get("name", ""),
        "away_team_id": away.get("id", ""),
        "away_team": away.get("name", ""),
        "home_score": score_total(scores.get("home")),
        "away_score": score_total(scores.get("away")),
    }


def publish_window(rows: list[dict[str, Any]], now: datetime) -> list[dict[str, Any]]:
    dated: list[tuple[datetime, dict[str, Any]]] = []
    for row in rows:
        raw = str(row.get("date_utc", "")).replace("Z", "+00:00")
        try:
            dt = datetime.fromisoformat(raw)
            dated.append((dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc), row))
        except ValueError:
            continue
    dated.sort(key=lambda item: item[0])
    start, end = now - timedelta(days=14), now + timedelta(days=14)
    window = [row for dt, row in dated if start <= dt <= end]
    if window:
        return window
    completed = [row for dt, row in dated if dt < now][-25:]
    upcoming = [row for dt, row in dated if dt >= now][:25]
    return completed + upcoming


def flatten_standings(node: Any) -> Iterable[dict[str, Any]]:
    if isinstance(node, dict):
        team = node.get("team")
        if isinstance(team, dict) and any(key in node for key in ("position", "rank", "games", "form")):
            yield node
        for value in node.values():
            yield from flatten_standings(value)
    elif isinstance(node, list):
        for value in node:
            yield from flatten_standings(value)


def standings_row(sport: str, item: dict[str, Any]) -> dict[str, Any]:
    team = item.get("team") if isinstance(item.get("team"), dict) else {}
    group = item.get("group") if isinstance(item.get("group"), dict) else {}
    games = item.get("games") if isinstance(item.get("games"), dict) else {}
    wins = games.get("win") if isinstance(games.get("win"), dict) else {}
    losses = games.get("lose") if isinstance(games.get("lose"), dict) else {}
    return {
        "sport": sport,
        "position": item.get("position", item.get("rank", "")),
        "group": group.get("name", item.get("group", "") if not isinstance(item.get("group"), dict) else ""),
        "team_id": team.get("id", ""),
        "team": team.get("name", ""),
        "played": games.get("played", item.get("played", "")),
        "wins": wins.get("total", item.get("win", item.get("wins", ""))),
        "losses": losses.get("total", item.get("lose", item.get("losses", ""))),
        "percentage": wins.get("percentage", item.get("percentage", "")),
        "form": item.get("form", ""),
    }


def write_csv(path: Path, rows: list[dict[str, Any]], fields: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def table_html(rows: list[dict[str, Any]], fields: list[tuple[str, str]], limit: int = 40) -> str:
    if not rows:
        return '<p class="empty">No rows returned for this snapshot.</p>'
    head = "".join(f"<th>{html.escape(label)}</th>" for _, label in fields)
    body = []
    for row in rows[:limit]:
        cells = "".join(f"<td>{html.escape(str(row.get(key, '')))}</td>" for key, _ in fields)
        body.append(f"<tr>{cells}</tr>")
    return f'<div class="table-wrap"><table><thead><tr>{head}</tr></thead><tbody>{"".join(body)}</tbody></table></div>'


def render_site(snapshots: dict[str, dict[str, Any]], refreshed: str) -> str:
    sections = []
    for sport, snapshot in snapshots.items():
        games = snapshot["games"]
        standings = snapshot["standings"]
        cfg = SPORTS[sport]
        sections.append(
            f"""
<section id="{sport}" class="panel">
  <div class="panel-head"><div><span class="kicker">{html.escape(sport)}</span><h2>{html.escape(cfg['label'])}</h2></div>
  <div class="metrics"><span><b>{len(games)}</b> published games</span><span><b>{len(standings)}</b> standings rows</span><span><b>{html.escape(str(snapshot['season']))}</b> season</span></div></div>
  <p>Resolved league: <b>{html.escape(str(snapshot['league_name']))}</b> (ID {html.escape(str(snapshot['league_id']))}).</p>
  <div class="downloads"><a href="data/{sport}_games.csv">Games CSV</a><a href="data/{sport}_standings.csv">Standings CSV</a><a href="data/{sport}_snapshot.json">Snapshot JSON</a></div>
  <h3>Recent and upcoming games</h3>
  {table_html(games, [('date_utc','UTC date'),('status','Status'),('away_team','Away'),('away_score','Score'),('home_team','Home'),('home_score','Score')])}
  <h3>Standings</h3>
  {table_html(standings, [('position','Pos'),('group','Group'),('team','Team'),('played','Played'),('wins','Wins'),('losses','Losses'),('percentage','Win %')])}
</section>
"""
        )
    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>LindaData Sports Data Hub</title>
<style>
:root{{--ink:#102a43;--muted:#627d98;--line:#d9e2ec;--bg:#f5f7fa;--card:#fff;--accent:#0b7285}}*{{box-sizing:border-box}}body{{margin:0;font-family:system-ui,-apple-system,Segoe UI,sans-serif;background:var(--bg);color:var(--ink)}}header{{background:var(--ink);color:#fff;padding:36px 20px}}header div,main{{max-width:1180px;margin:auto}}header h1{{margin:0 0 8px;font-size:clamp(2rem,5vw,3.5rem)}}header p{{margin:0;color:#d9e2ec}}nav{{margin-top:18px;display:flex;gap:10px;flex-wrap:wrap}}nav a,.downloads a{{display:inline-block;padding:8px 12px;border-radius:999px;text-decoration:none}}nav a{{background:#243b53;color:#fff}}main{{padding:24px 16px 60px}}.panel{{background:var(--card);border:1px solid var(--line);border-radius:16px;padding:22px;margin:0 0 24px;box-shadow:0 8px 24px rgba(16,42,67,.06)}}.panel-head{{display:flex;justify-content:space-between;gap:20px;align-items:flex-start;flex-wrap:wrap}}h2{{margin:2px 0 8px;font-size:1.8rem}}h3{{margin-top:28px}}.kicker{{text-transform:uppercase;letter-spacing:.12em;color:var(--accent);font-size:.75rem;font-weight:700}}.metrics{{display:flex;gap:10px;flex-wrap:wrap}}.metrics span{{background:#e6fcf5;padding:9px 12px;border-radius:10px;color:#0b5345}}.downloads{{display:flex;gap:8px;flex-wrap:wrap;margin:14px 0}}.downloads a{{background:#e3f2fd;color:#0b4f6c}}.table-wrap{{overflow:auto;border:1px solid var(--line);border-radius:12px}}table{{width:100%;border-collapse:collapse;min-width:720px}}th,td{{padding:10px 12px;text-align:left;border-bottom:1px solid var(--line);white-space:nowrap}}th{{background:#f0f4f8;position:sticky;top:0}}tr:last-child td{{border-bottom:0}}.empty{{color:var(--muted)}}footer{{text-align:center;color:var(--muted);padding:24px}}
</style></head><body>
<header><div><h1>Sports Data Hub</h1><p>API-Sports snapshots normalized and published from GitHub Actions. Last refreshed {html.escape(refreshed)}.</p><nav><a href="../">World Cup model</a><a href="#basketball">Basketball</a><a href="#baseball">Baseball</a><a href="data/manifest.json">Manifest</a></nav></div></header>
<main>{''.join(sections)}</main><footer>LindaData - Public summaries only; API credentials and raw feeds are not published.</footer>
</body></html>"""


def main() -> int:
    api_key = os.environ.get("API_SPORTS_KEY", "").strip()
    if not api_key:
        raise SystemExit("API_SPORTS_KEY is not set")

    now = utc_now()
    raw_dir = RAW_ROOT / now.strftime("%Y%m%dT%H%M%SZ")
    raw_dir.mkdir(parents=True, exist_ok=False)
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    snapshots: dict[str, dict[str, Any]] = {}
    quota_headers: dict[str, Any] = {}

    for sport, cfg in SPORTS.items():
        leagues_payload, headers = request_json(cfg["host"], "/leagues", api_key)
        quota_headers[sport] = headers
        league = choose_league(response_items(leagues_payload), cfg["league_name"], cfg["country"])
        season = select_season(league, sport, now)
        league_id = league.get("id")
        if league_id in (None, ""):
            raise RuntimeError(f"Resolved {sport} league has no ID")

        games_payload, headers = request_json(cfg["host"], "/games", api_key, {"league": league_id, "season": season})
        standings_payload, headers = request_json(cfg["host"], "/standings", api_key, {"league": league_id, "season": season})
        quota_headers[sport] = headers

        (raw_dir / f"{sport}_leagues.json").write_text(json.dumps(leagues_payload, indent=2), encoding="utf-8")
        (raw_dir / f"{sport}_games.json").write_text(json.dumps(games_payload, indent=2), encoding="utf-8")
        (raw_dir / f"{sport}_standings.json").write_text(json.dumps(standings_payload, indent=2), encoding="utf-8")

        all_games = [game_row(sport, item) for item in response_items(games_payload) if isinstance(item, dict)]
        games = publish_window(all_games, now)
        standings = [standings_row(sport, item) for item in flatten_standings(standings_payload.get("response", []))]

        game_fields = ["sport","game_id","date_utc","status","league_id","league","season","home_team_id","home_team","away_team_id","away_team","home_score","away_score"]
        standing_fields = ["sport","position","group","team_id","team","played","wins","losses","percentage","form"]
        write_csv(DATA_DIR / f"{sport}_games.csv", games, game_fields)
        write_csv(DATA_DIR / f"{sport}_standings.csv", standings, standing_fields)

        snapshot = {
            "sport": sport,
            "refreshed_at_utc": now.isoformat().replace("+00:00", "Z"),
            "league_id": league_id,
            "league_name": league.get("name", cfg["league_name"]),
            "season": season,
            "games": games,
            "standings": standings,
        }
        snapshots[sport] = snapshot
        (DATA_DIR / f"{sport}_snapshot.json").write_text(json.dumps(snapshot, indent=2), encoding="utf-8")

    refreshed = now.isoformat().replace("+00:00", "Z")
    manifest = {
        "refreshed_at_utc": refreshed,
        "sports": {key: {"league_id": value["league_id"], "season": value["season"], "published_games": len(value["games"]), "standings_rows": len(value["standings"])} for key, value in snapshots.items()},
        "quota_headers": quota_headers,
        "raw_artifact_directory": str(raw_dir.relative_to(ROOT)),
    }
    (DATA_DIR / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    (DOCS_DIR / "index.html").write_text(render_site(snapshots, refreshed), encoding="utf-8")
    print(json.dumps(manifest, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
