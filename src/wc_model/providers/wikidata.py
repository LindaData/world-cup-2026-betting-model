from __future__ import annotations

from wc_model.http import HttpClient, HttpResponse


class WikipediaPagePropsClient:
    def __init__(self, api_url: str, timeout_seconds: int = 30) -> None:
        self.api_url = api_url
        self.client = HttpClient(
            headers={"User-Agent": "world-cup-betting-data/0.1 (local research project)"},
            timeout_seconds=timeout_seconds,
        )

    def pageprops(self, titles: list[str]) -> HttpResponse:
        return self.client.get(
            self.api_url,
            params={
                "action": "query",
                "format": "json",
                "formatversion": "2",
                "prop": "pageprops",
                "titles": "|".join(titles),
            },
        )


class WikidataClient:
    def __init__(self, api_url: str, timeout_seconds: int = 30) -> None:
        self.api_url = api_url
        self.client = HttpClient(
            headers={"User-Agent": "world-cup-betting-data/0.1 (local research project)"},
            timeout_seconds=timeout_seconds,
        )

    def entities(self, qids: list[str]) -> HttpResponse:
        return self.client.get(
            self.api_url,
            params={
                "action": "wbgetentities",
                "format": "json",
                "props": "labels|claims|sitelinks",
                "languages": "en",
                "ids": "|".join(qids),
            },
        )

