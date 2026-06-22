from __future__ import annotations

from typing import Any

from wc_model.http import HttpClient, HttpResponse


class ApiSportsClient:
    """Generic thin client for API-Sports hosts."""

    def __init__(self, api_key: str, host: str) -> None:
        self.host = host
        self.client = HttpClient(
            base_url=f"https://{host}",
            headers={"x-apisports-key": api_key},
        )

    def get(self, path: str, params: dict[str, Any] | None = None) -> HttpResponse:
        return self.client.get(path, params=params)
