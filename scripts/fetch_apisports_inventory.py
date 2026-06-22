from __future__ import annotations

import argparse
import csv
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from wc_model.config import load_settings  # noqa: E402
from wc_model.providers.api_sports import ApiSportsClient  # noqa: E402


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def stamp(value: datetime) -> str:
    return value.strftime("%Y%m%dT%H%M%SZ")


def iso(value: datetime) -> str:
    return value.isoformat().replace("+00:00", "Z")


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")


def write_csv(path: Path, rows: list[dict[str, object]], fieldnames: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow({field: row.get(field, "") for field in fieldnames})


def clean_file_stem(value: str) -> str:
    return "".join(ch if ch.isalnum() or ch in {"_", "-"} else "_" for ch in value.lower())


def response_rows(payload: object) -> list[object]:
    if isinstance(payload, dict) and isinstance(payload.get("response"), list):
        return payload["response"]
    return []


def count_response_items(payload: object) -> int:
    if isinstance(payload, dict):
        results = payload.get("results")
        if isinstance(results, int):
            return results
        response = payload.get("response")
        if isinstance(response, list):
            return len(response)
        if isinstance(response, dict):
            return 1
    return 0


def compact_errors(payload: object) -> str:
    if not isinstance(payload, dict):
        return ""
    errors = payload.get("errors")
    if errors in ({}, [], None, ""):
        return ""
    return json.dumps(errors, sort_keys=True)


def paging_json(payload: object) -> str:
    if not isinstance(payload, dict) or not payload.get("paging"):
        return ""
    return json.dumps(payload["paging"], sort_keys=True)


def status_summary(payload: object) -> dict[str, object]:
    if not isinstance(payload, dict):
        return {}
    response = payload.get("response")
    if not isinstance(response, dict):
        return {}
    requests = response.get("requests") if isinstance(response.get("requests"), dict) else {}
    subscription = response.get("subscription") if isinstance(response.get("subscription"), dict) else {}
    return {
        "plan": subscription.get("plan", ""),
        "subscription_active": subscription.get("active", ""),
        "subscription_end": subscription.get("end", ""),
        "requests_current": requests.get("current", ""),
        "requests_limit_day": requests.get("limit_day", ""),
    }


def sample_fields(payload: object, max_fields: int = 24) -> str:
    rows = response_rows(payload)
    if not rows:
        response = payload.get("response") if isinstance(payload, dict) else None
        if isinstance(response, dict):
            rows = [response]
    if not rows or not isinstance(rows[0], dict):
        return ""
    return ", ".join(list(rows[0].keys())[:max_fields])


def load_sports_config(path: Path) -> dict[str, Any]:
    config = read_json(path)
    sports = config.get("sports")
    if not isinstance(sports, list) or not sports:
        raise ValueError(f"No sports found in {path}")
    return config


def select_sports(config: dict[str, Any], sport_keys: list[str]) -> list[dict[str, Any]]:
    sports = [sport for sport in config["sports"] if isinstance(sport, dict)]
    if not sport_keys or "all" in sport_keys:
        return sports
    wanted = set(sport_keys)
    selected = [sport for sport in sports if sport.get("sport_key") in wanted]
    missing = sorted(wanted - {sport.get("sport_key") for sport in selected})
    if missing:
        raise ValueError("Unknown sport key(s): " + ", ".join(missing))
    return selected


def endpoint_rows_for_sport(
    sport: dict[str, Any],
    client: ApiSportsClient,
    raw_root: Path,
    pulled_at_utc: str,
    dry_run: bool,
) -> tuple[list[dict[str, object]], dict[str, object]]:
    endpoint_rows: list[dict[str, object]] = []
    sport_status: dict[str, object] = {}
    endpoints = sport.get("inventory_endpoints") if isinstance(sport.get("inventory_endpoints"), list) else []

    for endpoint in endpoints:
        name = str(endpoint.get("name", "endpoint"))
        path = str(endpoint.get("path", ""))
        params = endpoint.get("params") if isinstance(endpoint.get("params"), dict) else {}
        raw_file = raw_root / str(sport["sport_key"]) / f"{clean_file_stem(name)}.json"
        row: dict[str, object] = {
            "pulled_at_utc": pulled_at_utc,
            "sport_key": sport["sport_key"],
            "sport_label": sport["label"],
            "host": sport["host"],
            "endpoint_name": name,
            "path": path,
            "params_json": json.dumps(params, sort_keys=True),
            "status_code": "",
            "results": "",
            "errors": "",
            "paging_json": "",
            "sample_fields": "",
            "raw_file": str(raw_file.relative_to(ROOT)),
        }
        if dry_run:
            endpoint_rows.append(row)
            continue

        try:
            response = client.get(path, params=params)
        except ConnectionError as exc:
            row["status_code"] = "connection_error"
            row["errors"] = str(exc)
            endpoint_rows.append(row)
            continue

        row["status_code"] = response.status_code
        try:
            payload = response.json()
        except json.JSONDecodeError:
            payload = {"raw_text": response.text}

        write_json(raw_file, payload)
        row["results"] = count_response_items(payload)
        row["errors"] = compact_errors(payload)
        row["paging_json"] = paging_json(payload)
        row["sample_fields"] = sample_fields(payload)
        if name == "status":
            sport_status = status_summary(payload)
        endpoint_rows.append(row)

    return endpoint_rows, sport_status


def build_field_dictionary(
    sports: list[dict[str, Any]],
    endpoint_rows: list[dict[str, object]],
) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    for sport in sports:
        rows.append(
            {
                "sport_key": sport["sport_key"],
                "field_name": "model_family",
                "definition": "Modeling family that controls baseline targets and validation rules.",
                "source": "config/sports.json",
                "sample_value": sport.get("model_family", ""),
            }
        )
        rows.append(
            {
                "sport_key": sport["sport_key"],
                "field_name": "historical_depth_note",
                "definition": "Provider-level historical depth note used for planning data pulls.",
                "source": "config/sports.json",
                "sample_value": sport.get("historical_depth_note", ""),
            }
        )
    for endpoint in endpoint_rows:
        fields = str(endpoint.get("sample_fields", ""))
        if not fields:
            continue
        rows.append(
            {
                "sport_key": endpoint["sport_key"],
                "field_name": f"{endpoint['endpoint_name']}_sample_fields",
                "definition": "Top-level fields observed in the first response record for this endpoint.",
                "source": endpoint["path"],
                "sample_value": fields,
            }
        )
    return rows


def main() -> int:
    parser = argparse.ArgumentParser(description="Fetch quota-light API-Sports inventory snapshots.")
    parser.add_argument("--config", default="config/sports.json")
    parser.add_argument("--sports", nargs="+", default=["all"])
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    settings = load_settings()
    api_key = settings.api_sports_key or settings.api_football_key
    if not api_key and not args.dry_run:
        raise RuntimeError("API_SPORTS_KEY or API_FOOTBALL_KEY must be set in .env.")

    config = load_sports_config(ROOT / args.config)
    selected_sports = select_sports(config, args.sports)
    pulled_at = utc_now()
    pulled_at_text = iso(pulled_at)
    run_id = stamp(pulled_at)
    raw_root = ROOT / "data" / "raw" / "apisports_inventory" / run_id
    processed_root = ROOT / "data" / "processed" / "multisport"

    endpoint_rows: list[dict[str, object]] = []
    sport_rows: list[dict[str, object]] = []
    manifest: dict[str, object] = {
        "pulled_at_utc": pulled_at_text,
        "run_id": run_id,
        "dry_run": args.dry_run,
        "sports": {},
    }

    for sport in selected_sports:
        client = ApiSportsClient(api_key, host=str(sport["host"]))
        sport_endpoint_rows, sport_status = endpoint_rows_for_sport(
            sport=sport,
            client=client,
            raw_root=raw_root,
            pulled_at_utc=pulled_at_text,
            dry_run=args.dry_run,
        )
        endpoint_rows.extend(sport_endpoint_rows)
        success_count = sum(1 for row in sport_endpoint_rows if str(row.get("status_code")) == "200")
        sport_row = {
            "pulled_at_utc": pulled_at_text,
            "sport_key": sport["sport_key"],
            "sport_label": sport["label"],
            "host": sport["host"],
            "api_version": sport.get("api_version", ""),
            "historical_depth_note": sport.get("historical_depth_note", ""),
            "reference_priority": sport.get("reference_priority", ""),
            "model_family": sport.get("model_family", ""),
            "endpoints_configured": len(sport_endpoint_rows),
            "endpoints_ok": success_count,
            "plan": sport_status.get("plan", ""),
            "subscription_active": sport_status.get("subscription_active", ""),
            "subscription_end": sport_status.get("subscription_end", ""),
            "requests_current": sport_status.get("requests_current", ""),
            "requests_limit_day": sport_status.get("requests_limit_day", ""),
        }
        sport_rows.append(sport_row)
        manifest["sports"][sport["sport_key"]] = {
            "host": sport["host"],
            "endpoints": [
                {
                    "name": row["endpoint_name"],
                    "path": row["path"],
                    "status_code": row["status_code"],
                    "results": row["results"],
                    "errors": row["errors"],
                    "raw_file": row["raw_file"],
                }
                for row in sport_endpoint_rows
            ],
        }

    field_rows = build_field_dictionary(selected_sports, endpoint_rows)

    write_csv(
        processed_root / "apisports_sport_inventory.csv",
        sport_rows,
        [
            "pulled_at_utc",
            "sport_key",
            "sport_label",
            "host",
            "api_version",
            "historical_depth_note",
            "reference_priority",
            "model_family",
            "endpoints_configured",
            "endpoints_ok",
            "plan",
            "subscription_active",
            "subscription_end",
            "requests_current",
            "requests_limit_day",
        ],
    )
    write_csv(
        processed_root / "apisports_endpoint_inventory.csv",
        endpoint_rows,
        [
            "pulled_at_utc",
            "sport_key",
            "sport_label",
            "host",
            "endpoint_name",
            "path",
            "params_json",
            "status_code",
            "results",
            "errors",
            "paging_json",
            "sample_fields",
            "raw_file",
        ],
    )
    write_csv(
        processed_root / "apisports_field_dictionary.csv",
        field_rows,
        ["sport_key", "field_name", "definition", "source", "sample_value"],
    )
    write_json(raw_root / "manifest.json", manifest)

    print(f"Wrote API-Sports inventory raw snapshot: {raw_root}")
    print(f"Wrote sanitized inventory tables: {processed_root}")
    print(f"Sports inventoried: {len(sport_rows)}")
    print(f"Endpoint rows: {len(endpoint_rows)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
