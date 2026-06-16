from __future__ import annotations

import re
from pathlib import Path

from wc_model.config import Settings
from wc_model.http import HttpClient, HttpResponse


def slugify_page(page: str) -> str:
    slug = page.strip().lower()
    slug = re.sub(r"[^a-z0-9]+", "_", slug)
    return slug.strip("_")


class WikimediaClient:
    def __init__(self, api_url: str, timeout_seconds: int = 30) -> None:
        self.client = HttpClient(
            headers={
                "User-Agent": (
                    "world-cup-betting-data/0.1 "
                    "(local research project; contact: user-managed)"
                )
            },
            timeout_seconds=timeout_seconds,
        )
        self.api_url = api_url

    def page_wikitext(self, page: str) -> HttpResponse:
        return self.client.get(
            self.api_url,
            params={
                "action": "query",
                "prop": "revisions",
                "titles": page,
                "rvprop": "content",
                "rvslots": "main",
                "format": "json",
                "formatversion": "2",
            },
        )


def extract_wikitext(payload: dict) -> str:
    pages = payload.get("query", {}).get("pages", [])
    if not pages:
        return ""
    page = pages[0]
    revisions = page.get("revisions", [])
    if not revisions:
        return ""
    slots = revisions[0].get("slots", {})
    main = slots.get("main", {})
    return main.get("content", "")


def download_wikimedia_pages(settings: Settings, destination_dir: Path) -> dict[str, HttpResponse]:
    client = WikimediaClient(settings.wikimedia_api_url)
    responses: dict[str, HttpResponse] = {}
    for page in settings.wikimedia_pages:
        slug = slugify_page(page)
        response = client.page_wikitext(page)
        responses[f"wikimedia_{slug}.json"] = response
        if response.ok:
            destination_dir.mkdir(parents=True, exist_ok=True)
            (destination_dir / f"wikimedia_{slug}.json").write_text(
                response.text,
                encoding="utf-8",
            )
            (destination_dir / f"wikimedia_{slug}.wikitext").write_text(
                extract_wikitext(response.json()),
                encoding="utf-8",
            )
    return responses
