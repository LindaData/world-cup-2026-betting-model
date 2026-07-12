"""Quota-aware odds snapshots from The Odds API (v4).

Two capture modes, decided per run so an hourly cron stays inside the free
tier (500 credits/month; one request costs ~markets x regions credits):

- daily: one snapshot per UTC day of upcoming events for each sport key.
- closing: when a fixture (from the published football fixtures feed) kicks
  off within ODDS_CLOSING_WINDOW_MINUTES and has no closing record yet,
  capture one snapshot and store per-event closing lines. Closing lines are
  the asset for CLV measurement - they cannot be fetched retroactively.

Outputs (committed by the workflow, public market facts only - model
comparisons stay private per the desk design):
- docs/sports-data/data/odds/odds_latest.json    normalized latest snapshot
- docs/sports-data/data/odds/closing/<id>.json   one file per event
- docs/sports-data/data/odds/odds_manifest.json  refresh time + credit usage
- docs/sports-data/data/odds/state.json          capture bookkeeping

Runs cleanly as a no-op when THE_ODDS_API_KEY is unset.
"""

from __future__ import annotations

import json
import os
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs" / "sports-data" / "data" / "odds"

BASE_URL = "https://api.the-odds-api.com/v4"

SPORT_KEYS = [s.strip() for s in os.environ.get("ODDS_SPORT_KEYS", "soccer_fifa_world_cup").split(",") if s.strip()]
OUTRIGHT_KEYS = [
    s.strip()
    for s in os.environ.get("ODDS_OUTRIGHT_KEYS", "soccer_fifa_world_cup_winner").split(",")
    if s.strip()
]
REGIONS = os.environ.get("ODDS_REGIONS", "us,eu").strip()
MARKETS = os.environ.get("ODDS_MARKETS", "h2h,spreads,totals").strip()
ODDS_FORMAT = os.environ.get("ODDS_ODDS_FORMAT", "decimal").strip()
CLOSING_WINDOW_MIN = int(os.environ.get("ODDS_CLOSING_WINDOW_MINUTES", "75"))
FIXTURES_FILE = ROOT / "docs" / "sports-data" / "data" / "football_fixtures.json"


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def iso(dt: datetime) -> str:
    return dt.isoformat().replace("+00:00", "Z")


def api_get(path: str, params: dict[str, Any]) -> tuple[Any, dict[str, str]]:
    params = {"apiKey": os.environ["THE_ODDS_API_KEY"], **params}
    url = f"{BASE_URL}{path}?{urlencode(params)}"
    request = Request(url, headers={"Accept": "application/json", "User-Agent": "LindaData-Sports-Hub/1.0"})
    try:
        with urlopen(request, timeout=60) as response:
            headers = {
                "requests_remaining": response.headers.get("x-requests-remaining", ""),
                "requests_used": response.headers.get("x-requests-used", ""),
            }
            return json.loads(response.read().decode("utf-8")), headers
    except HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"The Odds API HTTP {exc.code}: {body[:500]}") from exc
    except (URLError, TimeoutError) as exc:
        raise RuntimeError(f"The Odds API request failed: {exc}") from exc


def implied(price: float | None) -> float | None:
    if not price or price <= 1.0:
        return None
    return 1.0 / price


def normalize_event(event: dict[str, Any]) -> dict[str, Any]:
    """Flatten bookmaker markets and add best price + no-vig consensus."""
    markets: dict[str, dict[str, Any]] = {}
    for book in event.get("bookmakers") or []:
        book_key = book.get("key", "")
        for market in book.get("markets") or []:
            market_key = market.get("key", "")
            slot = markets.setdefault(market_key, {"outcomes": {}})
            for outcome in market.get("outcomes") or []:
                # Points (spread/total line) distinguish outcomes within a market.
                name = outcome.get("name", "")
                point = outcome.get("point")
                outcome_id = f"{name}@{point}" if point is not None else name
                entry = slot["outcomes"].setdefault(
                    outcome_id,
                    {"name": name, "point": point, "prices": {}, "best_price": None, "best_book": None},
                )
                price = outcome.get("price")
                if price is None:
                    continue
                entry["prices"][book_key] = price
                if entry["best_price"] is None or price > entry["best_price"]:
                    entry["best_price"] = price
                    entry["best_book"] = book_key

    # Per-book no-vig for h2h, then median across books as consensus.
    h2h = markets.get("h2h")
    if h2h:
        by_book: dict[str, dict[str, float]] = {}
        for outcome_id, entry in h2h["outcomes"].items():
            for book_key, price in entry["prices"].items():
                p = implied(price)
                if p:
                    by_book.setdefault(book_key, {})[outcome_id] = p
        novig_samples: dict[str, list[float]] = {}
        for book_key, probs in by_book.items():
            total = sum(probs.values())
            if total <= 0 or len(probs) < 2:
                continue
            for outcome_id, p in probs.items():
                novig_samples.setdefault(outcome_id, []).append(p / total)
        for outcome_id, samples in novig_samples.items():
            samples.sort()
            mid = len(samples) // 2
            median = samples[mid] if len(samples) % 2 else (samples[mid - 1] + samples[mid]) / 2
            h2h["outcomes"][outcome_id]["novig_consensus_prob"] = round(median, 6)

    return {
        "event_id": event.get("id", ""),
        "sport_key": event.get("sport_key", ""),
        "commence_time": event.get("commence_time", ""),
        "home_team": event.get("home_team", ""),
        "away_team": event.get("away_team", ""),
        "bookmaker_count": len(event.get("bookmakers") or []),
        "markets": markets,
    }


def load_json(path: Path, default: Any) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return default


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def fixtures_near_kickoff(now: datetime) -> list[dict[str, Any]]:
    fixtures = load_json(FIXTURES_FILE, [])
    horizon = now + timedelta(minutes=CLOSING_WINDOW_MIN)
    upcoming = []
    for fixture in fixtures if isinstance(fixtures, list) else []:
        raw = fixture.get("date_utc")
        if not raw:
            continue
        try:
            kickoff = datetime.fromisoformat(str(raw).replace("Z", "+00:00"))
        except ValueError:
            continue
        if now <= kickoff <= horizon:
            upcoming.append(fixture)
    return upcoming


def match_event(event: dict[str, Any], fixture: dict[str, Any]) -> bool:
    def norm(value: Any) -> str:
        return str(value or "").strip().lower()

    home, away = norm(fixture.get("home_team")), norm(fixture.get("away_team"))
    eh, ea = norm(event.get("home_team")), norm(event.get("away_team"))
    if not (home and away and eh and ea):
        return False
    return (home in eh or eh in home) and (away in ea or ea in away)


def main() -> int:
    if not os.environ.get("THE_ODDS_API_KEY", "").strip():
        print("THE_ODDS_API_KEY is not set; skipping odds snapshot (no-op).")
        return 0

    now = utc_now()
    today = now.strftime("%Y-%m-%d")
    state = load_json(OUT / "state.json", {"last_daily_date": "", "closing_captured": []})
    captured: set[str] = set(state.get("closing_captured") or [])

    need_daily = state.get("last_daily_date") != today
    near_kickoff = fixtures_near_kickoff(now)
    pending_closing = [f for f in near_kickoff if str(f.get("game_id")) not in captured]

    if not need_daily and not pending_closing:
        print("Nothing to capture this run (daily done, no fixtures near kickoff).")
        return 0

    credits: dict[str, str] = {}
    latest_events: list[dict[str, Any]] = []
    outrights: list[dict[str, Any]] = []

    for sport_key in SPORT_KEYS:
        payload, credits = api_get(
            f"/sports/{sport_key}/odds",
            {"regions": REGIONS, "markets": MARKETS, "oddsFormat": ODDS_FORMAT, "dateFormat": "iso"},
        )
        latest_events.extend(normalize_event(event) for event in payload or [])

    if need_daily:
        for outright_key in OUTRIGHT_KEYS:
            try:
                payload, credits = api_get(
                    f"/sports/{outright_key}/odds",
                    {"regions": REGIONS, "markets": "outrights", "oddsFormat": ODDS_FORMAT, "dateFormat": "iso"},
                )
                outrights.extend(normalize_event(event) for event in payload or [])
            except RuntimeError as exc:
                print(f"Outright fetch failed for {outright_key} (continuing): {exc}")
        state["last_daily_date"] = today

    snapshot = {
        "captured_at_utc": iso(now),
        "regions": REGIONS,
        "markets": MARKETS,
        "events": latest_events,
        "outrights": outrights or load_json(OUT / "odds_latest.json", {}).get("outrights", []),
    }
    write_json(OUT / "odds_latest.json", snapshot)

    closing_written = 0
    for fixture in pending_closing:
        game_id = str(fixture.get("game_id"))
        matched = next((e for e in latest_events if match_event(e, fixture)), None)
        if matched is None:
            continue
        write_json(
            OUT / "closing" / f"{game_id}.json",
            {"game_id": game_id, "captured_at_utc": iso(now), "minutes_to_kickoff_max": CLOSING_WINDOW_MIN, **matched},
        )
        captured.add(game_id)
        closing_written += 1

    state["closing_captured"] = sorted(captured)
    write_json(OUT / "state.json", state)
    write_json(
        OUT / "odds_manifest.json",
        {
            "refreshed_at_utc": iso(now),
            "provider": "The Odds API v4",
            "sport_keys": SPORT_KEYS,
            "regions": REGIONS,
            "markets": MARKETS,
            "event_count": len(latest_events),
            "closing_files_written_this_run": closing_written,
            "credits_used": credits.get("requests_used", ""),
            "credits_remaining": credits.get("requests_remaining", ""),
        },
    )
    print(
        json.dumps(
            {
                "daily_snapshot": need_daily,
                "events": len(latest_events),
                "closing_written": closing_written,
                "credits_remaining": credits.get("requests_remaining", ""),
            },
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
