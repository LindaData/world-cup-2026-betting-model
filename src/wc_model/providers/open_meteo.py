from __future__ import annotations

from wc_model.http import HttpClient, HttpResponse


class OpenMeteoClient:
    """Weather context provider. No key required."""

    def __init__(self) -> None:
        self.forecast_client = HttpClient(base_url="https://api.open-meteo.com/v1")
        self.archive_client = HttpClient(base_url="https://archive-api.open-meteo.com/v1")

    def forecast_hourly(
        self,
        latitude: float,
        longitude: float,
        start_date: str,
        end_date: str,
        timezone: str = "auto",
    ) -> HttpResponse:
        hourly = ",".join(
            [
                "temperature_2m",
                "relative_humidity_2m",
                "precipitation",
                "wind_speed_10m",
            ]
        )
        return self.forecast_client.get(
            "/forecast",
            params={
                "latitude": latitude,
                "longitude": longitude,
                "start_date": start_date,
                "end_date": end_date,
                "hourly": hourly,
                "timezone": timezone,
            },
        )

    def archive_hourly(
        self,
        latitude: float,
        longitude: float,
        start_date: str,
        end_date: str,
        timezone: str = "auto",
    ) -> HttpResponse:
        hourly = ",".join(
            [
                "temperature_2m",
                "relative_humidity_2m",
                "precipitation",
                "wind_speed_10m",
            ]
        )
        return self.archive_client.get(
            "/archive",
            params={
                "latitude": latitude,
                "longitude": longitude,
                "start_date": start_date,
                "end_date": end_date,
                "hourly": hourly,
                "timezone": timezone,
            },
        )

