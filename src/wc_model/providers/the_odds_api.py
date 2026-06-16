from __future__ import annotations

from typing import Any

from wc_model.http import HttpClient, HttpResponse


class TheOddsApiClient:
    """Thin client for The Odds API v4."""

    def __init__(self, api_key: str, timeout_seconds: int = 30) -> None:
        self.api_key = api_key
        self.client = HttpClient(
            base_url="https://api.the-odds-api.com/v4",
            timeout_seconds=timeout_seconds,
        )

    def sports(self, all_sports: bool = False) -> HttpResponse:
        return self.client.get("/sports", params={"apiKey": self.api_key, "all": str(all_sports).lower()})

    def odds(
        self,
        sport: str,
        regions: str = "us",
        markets: str = "h2h,spreads,totals",
        odds_format: str = "decimal",
        date_format: str = "iso",
        **extra: Any,
    ) -> HttpResponse:
        params = {
            "apiKey": self.api_key,
            "regions": regions,
            "markets": markets,
            "oddsFormat": odds_format,
            "dateFormat": date_format,
            **extra,
        }
        return self.client.get(f"/sports/{sport}/odds", params=params)

    def events(self, sport: str) -> HttpResponse:
        return self.client.get(f"/sports/{sport}/events", params={"apiKey": self.api_key})

    def event_markets(
        self,
        sport: str,
        event_id: str,
        regions: str = "us",
        date_format: str = "iso",
    ) -> HttpResponse:
        return self.client.get(
            f"/sports/{sport}/events/{event_id}/markets",
            params={"apiKey": self.api_key, "regions": regions, "dateFormat": date_format},
        )

    @staticmethod
    def discover_world_cup_sports(sports_payload: list[dict[str, Any]]) -> list[dict[str, Any]]:
        candidates = []
        for sport in sports_payload:
            haystack = " ".join(
                str(sport.get(field, "")) for field in ("key", "group", "title", "description")
            ).lower()
            if "soccer" in haystack and ("world cup" in haystack or "fifa" in haystack):
                candidates.append(sport)
        return candidates

