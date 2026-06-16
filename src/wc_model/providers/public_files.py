from __future__ import annotations

from pathlib import Path

from wc_model.config import Settings
from wc_model.http import HttpClient, HttpResponse


PUBLIC_SOURCES = {
    "openfootball_cup.txt": "openfootball_cup_url",
    "openfootball_stadiums.csv": "openfootball_stadiums_url",
    "international_results.csv": "international_results_url",
    "international_goalscorers.csv": "international_goalscorers_url",
    "international_shootouts.csv": "international_shootouts_url",
}


def download_public_sources(settings: Settings, destination_dir: Path) -> dict[str, HttpResponse]:
    client = HttpClient()
    responses: dict[str, HttpResponse] = {}
    for filename, setting_name in PUBLIC_SOURCES.items():
        url = getattr(settings, setting_name)
        responses[filename] = client.download(url, destination_dir / filename)
    return responses

