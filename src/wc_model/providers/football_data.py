from __future__ import annotations

from typing import Any

from wc_model.http import HttpClient, HttpResponse


class FootballDataClient:
    """Thin client for football-data.org v4."""

    def __init__(self, token: str, timeout_seconds: int = 30) -> None:
        self.client = HttpClient(
            base_url="https://api.football-data.org/v4",
            headers={"X-Auth-Token": token},
            timeout_seconds=timeout_seconds,
        )

    def competitions(self) -> HttpResponse:
        return self.client.get("/competitions")

    def competition_matches(
        self,
        competition: str = "WC",
        season: int = 2026,
        **filters: Any,
    ) -> HttpResponse:
        params = {"season": season, **filters}
        return self.client.get(f"/competitions/{competition}/matches", params=params)

    def competition_teams(self, competition: str = "WC", season: int = 2026) -> HttpResponse:
        return self.client.get(f"/competitions/{competition}/teams", params={"season": season})

    def competition_standings(self, competition: str = "WC", season: int = 2026) -> HttpResponse:
        return self.client.get(f"/competitions/{competition}/standings", params={"season": season})

