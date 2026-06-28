from __future__ import annotations

import argparse
import json
import os
import re
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


HOSTS = {
    "football": "v3.football.api-sports.io",
    "baseball": "v1.baseball.api-sports.io",
    "basketball": "v1.basketball.api-sports.io",
}
SAFE_ENDPOINT = re.compile(r"^[A-Za-z0-9_/-]+$")


def utc_stamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def parse_params(env_name: str) -> dict[str, Any]:
    raw = os.environ.get(env_name, "{}").strip() or "{}"
    try:
        value = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"{env_name} must contain valid JSON: {exc}") from exc
    if not isinstance(value, dict):
        raise SystemExit(f"{env_name} must contain a JSON object.")
    return value


def validate_endpoint(endpoint: str) -> str:
    endpoint = endpoint.strip().strip("/")
    if not endpoint or not SAFE_ENDPOINT.fullmatch(endpoint) or ".." in endpoint:
        raise SystemExit("Endpoint may contain only letters, numbers, _, -, and /.")
    return endpoint


def selected_headers(headers: Any) -> dict[str, str]:
    keep = {
        "x-ratelimit-requests-limit",
        "x-ratelimit-requests-remaining",
        "x-ratelimit-remaining",
        "retry-after",
    }
    return {key.lower(): value for key, value in headers.items() if key.lower() in keep}


def request_json(url: str, api_key: str, retries: int = 4) -> tuple[dict[str, Any], int, dict[str, str]]:
    request = Request(
        url,
        headers={
            "x-apisports-key": api_key,
            "Accept": "application/json",
            "User-Agent": "LindaData-GitHub-Actions/1.0",
        },
    )

    for attempt in range(retries + 1):
        try:
            with urlopen(request, timeout=60) as response:
                body = response.read().decode("utf-8")
                payload = json.loads(body)
                if not isinstance(payload, dict):
                    raise RuntimeError("API response was not a JSON object.")
                return payload, response.status, selected_headers(response.headers)
        except HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")
            retryable = exc.code == 429 or 500 <= exc.code < 600
            if retryable and attempt < retries:
                retry_after = exc.headers.get("Retry-After")
                delay = int(retry_after) if retry_after and retry_after.isdigit() else 2**attempt
                time.sleep(min(delay, 30))
                continue
            raise RuntimeError(f"API request failed with HTTP {exc.code}: {body[:1000]}") from exc
        except (URLError, TimeoutError) as exc:
            if attempt < retries:
                time.sleep(min(2**attempt, 30))
                continue
            raise RuntimeError(f"API request failed after retries: {exc}") from exc
        except json.JSONDecodeError as exc:
            raise RuntimeError("API returned invalid JSON.") from exc

    raise RuntimeError("API request failed unexpectedly.")


def write_summary(manifest: dict[str, Any]) -> None:
    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if not summary_path:
        return
    lines = [
        "## API-Sports pull",
        "",
        f"- Sport: `{manifest['sport']}`",
        f"- Endpoint: `/{manifest['endpoint']}`",
        f"- Pages saved: **{manifest['pages_saved']}**",
        f"- Records reported: **{manifest['records_reported']}**",
        f"- Output: `{manifest['output_directory']}`",
    ]
    headers = manifest.get("last_response_headers", {})
    if headers:
        lines.extend(["", "### Quota headers", ""])
        lines.extend(f"- `{key}`: `{value}`" for key, value in headers.items())
    Path(summary_path).write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Pull paginated data from an API-Sports product.")
    parser.add_argument("--sport", choices=sorted(HOSTS), required=True)
    parser.add_argument("--endpoint", required=True, help="Endpoint without the leading slash, for example games.")
    parser.add_argument("--params-env", default="API_SPORTS_PARAMS")
    parser.add_argument("--max-pages", type=int, default=25)
    parser.add_argument("--output-dir", default="data/raw/api_sports")
    args = parser.parse_args()

    if not 1 <= args.max_pages <= 1000:
        raise SystemExit("--max-pages must be between 1 and 1000.")

    api_key = os.environ.get("API_SPORTS_KEY", "").strip()
    if not api_key:
        raise SystemExit("API_SPORTS_KEY is not set.")

    endpoint = validate_endpoint(args.endpoint)
    params = parse_params(args.params_env)
    start_page = int(params.pop("page", 1))
    host = HOSTS[args.sport]
    run_dir = Path(args.output_dir) / f"{utc_stamp()}_{args.sport}_{endpoint.replace('/', '_')}"
    run_dir.mkdir(parents=True, exist_ok=False)

    pages_saved = 0
    records_reported = 0
    last_headers: dict[str, str] = {}
    first_url = ""

    for page in range(start_page, start_page + args.max_pages):
        page_params = dict(params)
        if args.max_pages > 1 or start_page != 1:
            page_params["page"] = page
        query = urlencode(page_params, doseq=True)
        url = f"https://{host}/{endpoint}" + (f"?{query}" if query else "")
        if not first_url:
            first_url = url

        payload, status, response_headers = request_json(url, api_key)
        last_headers = response_headers
        output = run_dir / f"page_{page:04d}.json"
        output.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")
        pages_saved += 1

        response_items = payload.get("response")
        if isinstance(response_items, list):
            records_reported += len(response_items)

        errors = payload.get("errors")
        if errors and errors not in ({}, []):
            raise RuntimeError(f"API returned errors; inspect {output}: {errors}")

        paging = payload.get("paging")
        if not isinstance(paging, dict):
            break
        current = int(paging.get("current") or page)
        total = int(paging.get("total") or current)
        if current >= total:
            break

        time.sleep(0.25)

    manifest = {
        "created_at_utc": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "sport": args.sport,
        "host": host,
        "endpoint": endpoint,
        "parameters": params,
        "first_request_url": first_url,
        "pages_saved": pages_saved,
        "records_reported": records_reported,
        "last_response_headers": last_headers,
        "output_directory": str(run_dir),
    }
    (run_dir / "manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True), encoding="utf-8"
    )
    write_summary(manifest)
    print(json.dumps(manifest, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
