from __future__ import annotations

import argparse
import csv
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from wc_model.config import load_settings  # noqa: E402
from wc_model.providers.wikidata import WikidataClient, WikipediaPagePropsClient  # noqa: E402


def chunks(values: list[str], size: int) -> Iterable[list[str]]:
    for index in range(0, len(values), size):
        yield values[index : index + size]


def read_squad_titles() -> list[dict[str, str]]:
    path = ROOT / "data" / "processed" / "public_csv" / "dim_2026_world_cup_squad_players.csv"
    with path.open("r", encoding="utf-8", newline="") as handle:
        return [row for row in csv.DictReader(handle) if row.get("player_wiki_title")]


def write_csv(path: Path, rows: list[dict[str, object]], fieldnames: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")


def claim_values(entity: dict[str, Any], prop: str) -> list[Any]:
    values = []
    for claim in entity.get("claims", {}).get(prop, []):
        mainsnak = claim.get("mainsnak", {})
        datavalue = mainsnak.get("datavalue", {})
        if "value" in datavalue:
            values.append(datavalue["value"])
    return values


def first_time(entity: dict[str, Any], prop: str) -> str:
    values = claim_values(entity, prop)
    if not values:
        return ""
    value = values[0]
    if isinstance(value, dict):
        return str(value.get("time", "")).lstrip("+")
    return ""


def first_quantity(entity: dict[str, Any], prop: str) -> float | None:
    values = claim_values(entity, prop)
    if not values:
        return None
    value = values[0]
    if not isinstance(value, dict):
        return None
    amount = value.get("amount")
    try:
        return float(amount)
    except (TypeError, ValueError):
        return None


def entity_ids(entity: dict[str, Any], prop: str) -> str:
    ids = []
    for value in claim_values(entity, prop):
        if isinstance(value, dict) and value.get("entity-type") == "item":
            ids.append(f"Q{value.get('numeric-id')}")
    return "|".join(ids)


def first_string(entity: dict[str, Any], prop: str) -> str:
    values = claim_values(entity, prop)
    if not values:
        return ""
    return str(values[0])


def main() -> int:
    parser = argparse.ArgumentParser(description="Fetch Wikidata IDs and selected player metadata.")
    parser.add_argument("--batch-size", type=int, default=50)
    args = parser.parse_args()

    settings = load_settings()
    squad_rows = read_squad_titles()
    titles = sorted({row["player_wiki_title"] for row in squad_rows if row.get("player_wiki_title")})

    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    raw_dir = settings.root / "data" / "raw" / "wikidata" / stamp
    processed_dir = settings.root / "data" / "processed" / "public_csv"

    pageprops_client = WikipediaPagePropsClient(settings.wikipedia_api_url)
    wikidata_client = WikidataClient(settings.wikidata_api_url)

    title_to_qid: dict[str, str] = {}
    manifest: dict[str, Any] = {
        "pulled_at_utc": datetime.now(timezone.utc).isoformat(),
        "title_count": len(titles),
        "pageprops_batches": [],
        "entity_batches": [],
    }

    for batch_index, title_batch in enumerate(chunks(titles, args.batch_size), start=1):
        response = pageprops_client.pageprops(title_batch)
        manifest["pageprops_batches"].append({"batch": batch_index, "status_code": response.status_code, "url": response.url})
        write_json(raw_dir / f"pageprops_{batch_index:03d}.json", response.json() if response.ok else {"error": response.text})
        if not response.ok:
            continue
        for page in response.json().get("query", {}).get("pages", []):
            title = page.get("title", "")
            qid = page.get("pageprops", {}).get("wikibase_item", "")
            if title and qid:
                title_to_qid[title] = qid

    qids = sorted(set(title_to_qid.values()))
    qid_to_entity: dict[str, dict[str, Any]] = {}
    for batch_index, qid_batch in enumerate(chunks(qids, args.batch_size), start=1):
        response = wikidata_client.entities(qid_batch)
        manifest["entity_batches"].append({"batch": batch_index, "status_code": response.status_code, "url": response.url})
        write_json(raw_dir / f"entities_{batch_index:03d}.json", response.json() if response.ok else {"error": response.text})
        if not response.ok:
            continue
        qid_to_entity.update(response.json().get("entities", {}))

    output_rows: list[dict[str, object]] = []
    for row in squad_rows:
        title = row.get("player_wiki_title", "")
        qid = title_to_qid.get(title, "")
        entity = qid_to_entity.get(qid, {})
        output_rows.append(
            {
                "team": row.get("team", ""),
                "player_name": row.get("player_name", ""),
                "player_wiki_title": title,
                "wikidata_qid": qid,
                "wikidata_label": entity.get("labels", {}).get("en", {}).get("value", ""),
                "date_of_birth": first_time(entity, "P569"),
                "height_m": first_quantity(entity, "P2048"),
                "image": first_string(entity, "P18"),
                "country_of_citizenship_qids": entity_ids(entity, "P27"),
                "position_played_qids": entity_ids(entity, "P413"),
                "club_or_team_qids": entity_ids(entity, "P54"),
                "raw_entity_available": bool(entity),
            }
        )

    write_json(raw_dir / "manifest.json", manifest)
    write_csv(
        processed_dir / "dim_player_wikidata.csv",
        output_rows,
        [
            "team",
            "player_name",
            "player_wiki_title",
            "wikidata_qid",
            "wikidata_label",
            "date_of_birth",
            "height_m",
            "image",
            "country_of_citizenship_qids",
            "position_played_qids",
            "club_or_team_qids",
            "raw_entity_available",
        ],
    )
    print(f"Wrote {len(output_rows)} player Wikidata rows")
    print(f"Matched QIDs: {sum(1 for row in output_rows if row['wikidata_qid'])}")
    print(f"Raw Wikidata snapshot: {raw_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

