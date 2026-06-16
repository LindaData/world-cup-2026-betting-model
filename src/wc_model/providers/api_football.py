from __future__ import annotations

from wc_model.http import HttpClient, HttpResponse


class ApiFootballClient:
    """Thin client for API-Football / API-SPORTS v3."""

    def __init__(self, api_key: str, host: str = "v3.football.api-sports.io") -> None:
        self.client = HttpClient(
            base_url=f"https://{host}",
            headers={"x-apisports-key": api_key},
        )

    def leagues(self, search: str = "World Cup") -> HttpResponse:
        return self.client.get("/leagues", params={"search": search})

    def fixtures(self, league: str, season: int = 2026) -> HttpResponse:
        return self.client.get("/fixtures", params={"league": league, "season": season})

    def teams(self, league: str, season: int = 2026) -> HttpResponse:
        return self.client.get("/teams", params={"league": league, "season": season})

    def squads(self, team: str) -> HttpResponse:
        return self.client.get("/players/squads", params={"team": team})

    def players(self, league: str, season: int = 2026, page: int = 1) -> HttpResponse:
        return self.client.get(
            "/players",
            params={"league": league, "season": season, "page": page},
        )

    def standings(self, league: str, season: int = 2026) -> HttpResponse:
        return self.client.get("/standings", params={"league": league, "season": season})

    def odds(self, league: str, season: int = 2026) -> HttpResponse:
        return self.client.get("/odds", params={"league": league, "season": season})

    def fixture_lineups(self, fixture: str) -> HttpResponse:
        return self.client.get("/fixtures/lineups", params={"fixture": fixture})

    def fixture_events(self, fixture: str) -> HttpResponse:
        return self.client.get("/fixtures/events", params={"fixture": fixture})

    def fixture_player_statistics(self, fixture: str) -> HttpResponse:
        return self.client.get("/fixtures/players", params={"fixture": fixture})
