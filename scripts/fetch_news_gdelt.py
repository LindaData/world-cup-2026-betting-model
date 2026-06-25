from __future__ import annotations

import argparse
import csv
import json
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from wc_model.config import load_settings  # noqa: E402
from wc_model.providers.gdelt import GdeltDocClient, normalize_article  # noqa: E402


def read_team_queries() -> list[str]:
    squad_path = ROOT / "data" / "processed" / "public_csv" / "dim_2026_world_cup_squad_players.csv"
    if not squad_path.exists():
        return []
    with squad_path.open("r", encoding="utf-8", newline="") as handle:
        teams = sorted({row["team"] for row in csv.DictReader(handle) if row.get("team")})
    return [f'"{team}" "World Cup 2026"' for team in teams]


def write_csv(path: Path, rows: list[dict[str, object]], fieldnames: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Fetch World Cup news metadata from GDELT.")
    parser.add_argument(
        "--include-team-queries",
        action="store_true",
        help="Also search one GDELT query per 2026 World Cup team.",
    )
    parser.add_argument("--max-records", type=int, default=None)
    parser.add_argument("--timespan", default=None)
    args = parser.parse_args()

    settings = load_settings()
    queries = list(settings.gdelt_news_queries)
    if args.include_team_queries:
        queries.extend(read_team_queries())

    max_records = args.max_records or settings.gdelt_max_records_per_query
    timespan = args.timespan or settings.gdelt_timespan
    client = GdeltDocClient(settings.gdelt_doc_api_url)

    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    raw_dir = settings.root / "data" / "raw" / "news" / stamp
    processed_dir = settings.root / "data" / "processed" / "public_csv"

    articles: list[dict[str, object]] = []
    manifest: dict[str, object] = {
        "pulled_at_utc": datetime.now(timezone.utc).isoformat(),
        "source": "GDELT DOC 2.0 ArtList",
        "timespan": timespan,
        "max_records_per_query": max_records,
        "queries": {},
    }

    seen_urls: set[str] = set()
    for index, query in enumerate(queries, start=1):
        query_key = f"query_{index:03d}"
        try:
            response = client.article_list(query, max_records=max_records, timespan=timespan)
        except (ConnectionError, TimeoutError) as exc:
            manifest["queries"][query_key] = {
                "query": query,
                "status": "request_failed",
                "error": str(exc),
            }
            write_json(raw_dir / f"{query_key}.json", {"error": str(exc)})
            continue

        manifest["queries"][query_key] = {
            "query": query,
            "status_code": response.status_code,
            "url": response.url,
        }

        try:
            payload = response.json()
        except json.JSONDecodeError:
            payload = {
                "error": "GDELT returned a non-JSON response.",
                "response_preview": response.text[:500],
            }
            manifest["queries"][query_key]["status"] = "invalid_json"

        write_json(raw_dir / f"{query_key}.json", payload)
        if not response.ok:
            continue
        if not isinstance(payload, dict) or not isinstance(payload.get("articles"), list):
            continue

        for article in payload["articles"]:
            normalized = normalize_article(query, article)
            url = str(normalized["url"])
            if not url or url in seen_urls:
                continue
            seen_urls.add(url)
            normalized["pulled_at_utc"] = manifest["pulled_at_utc"]
            articles.append(normalized)

    write_json(raw_dir / "manifest.json", manifest)
    write_csv(
        processed_dir / "fact_news_articles_gdelt.csv",
        articles,
        [
            "pulled_at_utc",
            "query",
            "url",
            "title",
            "seendate",
            "domain",
            "language",
            "sourcecountry",
            "socialimage",
        ],
    )

    query_counts = Counter(str(article["query"]) for article in articles)
    write_csv(
        processed_dir / "agg_news_query_counts_gdelt.csv",
        [{"query": query, "articles": count} for query, count in sorted(query_counts.items())],
        ["query", "articles"],
    )
    print(f"Wrote {len(articles)} unique GDELT article metadata rows")
    print(f"Raw news snapshot: {raw_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
