from __future__ import annotations

from typing import Any

from wc_model.http import HttpClient, HttpResponse


class GdeltDocClient:
    """Thin client for the free GDELT 2.0 DOC API."""

    def __init__(self, api_url: str, timeout_seconds: int = 30) -> None:
        self.api_url = api_url
        self.client = HttpClient(
            headers={
                "User-Agent": (
                    "world-cup-betting-data/0.1 "
                    "(local research project; contact: user-managed)"
                )
            },
            timeout_seconds=timeout_seconds,
        )

    def article_list(
        self,
        query: str,
        max_records: int = 75,
        timespan: str = "7d",
        sort: str = "HybridRel",
    ) -> HttpResponse:
        return self.client.get(
            self.api_url,
            params={
                "query": query,
                "mode": "ArtList",
                "format": "json",
                "maxrecords": max_records,
                "timespan": timespan,
                "sort": sort,
            },
        )


def normalize_article(query: str, article: dict[str, Any]) -> dict[str, object]:
    return {
        "query": query,
        "url": article.get("url", ""),
        "title": article.get("title", ""),
        "seendate": article.get("seendate", ""),
        "domain": article.get("domain", ""),
        "language": article.get("language", ""),
        "sourcecountry": article.get("sourcecountry", ""),
        "socialimage": article.get("socialimage", ""),
    }

