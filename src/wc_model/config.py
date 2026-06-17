from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


def project_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _parse_env_file(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.exists():
        return values

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key:
            values[key] = value
    return values


def _get(name: str, env_file_values: dict[str, str], default: str = "") -> str:
    return os.environ.get(name, env_file_values.get(name, default))


@dataclass(frozen=True)
class Settings:
    root: Path
    football_data_token: str
    football_data_world_cup_competition: str
    football_data_season: int
    odds_api_key: str
    odds_api_sport_key: str
    odds_regions: str
    odds_markets: str
    odds_format: str
    api_football_key: str
    api_football_host: str
    api_football_world_cup_league_id: str
    api_football_season: int
    openfootball_cup_url: str
    openfootball_stadiums_url: str
    international_results_url: str
    international_goalscorers_url: str
    international_shootouts_url: str
    wikimedia_api_url: str
    wikimedia_pages: tuple[str, ...]
    fifa_2026_squad_pdf_url: str
    gdelt_doc_api_url: str
    gdelt_max_records_per_query: int
    gdelt_timespan: str
    gdelt_news_queries: tuple[str, ...]
    wikidata_api_url: str
    wikipedia_api_url: str


def load_settings(env_path: Path | None = None) -> Settings:
    root = project_root()
    env_file_values = _parse_env_file(env_path or root / ".env")

    return Settings(
        root=root,
        football_data_token=_get("FOOTBALL_DATA_TOKEN", env_file_values),
        football_data_world_cup_competition=_get(
            "FOOTBALL_DATA_WORLD_CUP_COMPETITION", env_file_values, "WC"
        ),
        football_data_season=int(_get("FOOTBALL_DATA_SEASON", env_file_values, "2026")),
        odds_api_key=_get("THE_ODDS_API_KEY", env_file_values),
        odds_api_sport_key=_get("ODDS_API_SPORT_KEY", env_file_values, "soccer_fifa_world_cup"),
        odds_regions=_get("ODDS_REGIONS", env_file_values, "us"),
        odds_markets=_get("ODDS_MARKETS", env_file_values, "h2h,spreads,totals"),
        odds_format=_get("ODDS_ODDS_FORMAT", env_file_values, "decimal"),
        api_football_key=_get("API_FOOTBALL_KEY", env_file_values),
        api_football_host=_get("API_FOOTBALL_HOST", env_file_values, "v3.football.api-sports.io"),
        api_football_world_cup_league_id=_get(
            "API_FOOTBALL_WORLD_CUP_LEAGUE_ID", env_file_values, "1"
        ),
        api_football_season=int(_get("API_FOOTBALL_SEASON", env_file_values, "2026")),
        openfootball_cup_url=_get(
            "OPENFOOTBALL_CUP_URL",
            env_file_values,
            "https://raw.githubusercontent.com/openfootball/worldcup/master/2026--usa/cup.txt",
        ),
        openfootball_stadiums_url=_get(
            "OPENFOOTBALL_STADIUMS_URL",
            env_file_values,
            "https://raw.githubusercontent.com/openfootball/worldcup/master/2026--usa/cup_stadiums.csv",
        ),
        international_results_url=_get(
            "INTERNATIONAL_RESULTS_URL",
            env_file_values,
            "https://raw.githubusercontent.com/martj42/international_results/master/results.csv",
        ),
        international_goalscorers_url=_get(
            "INTERNATIONAL_GOALSCORERS_URL",
            env_file_values,
            "https://raw.githubusercontent.com/martj42/international_results/master/goalscorers.csv",
        ),
        international_shootouts_url=_get(
            "INTERNATIONAL_SHOOTOUTS_URL",
            env_file_values,
            "https://raw.githubusercontent.com/martj42/international_results/master/shootouts.csv",
        ),
        wikimedia_api_url=_get(
            "WIKIMEDIA_API_URL",
            env_file_values,
            "https://en.wikipedia.org/w/api.php",
        ),
        wikimedia_pages=tuple(
            page.strip()
            for page in _get(
                "WIKIMEDIA_PAGES",
                env_file_values,
                "2026 FIFA World Cup,2026 FIFA World Cup squads,2026 FIFA World Cup officials",
            ).split(",")
            if page.strip()
        ),
        fifa_2026_squad_pdf_url=_get(
            "FIFA_2026_SQUAD_PDF_URL",
            env_file_values,
            "https://fdp.fifa.org/assetspublic/ce281/pdf/SquadLists-English.pdf",
        ),
        gdelt_doc_api_url=_get(
            "GDELT_DOC_API_URL",
            env_file_values,
            "https://api.gdeltproject.org/api/v2/doc/doc",
        ),
        gdelt_max_records_per_query=int(_get("GDELT_MAX_RECORDS_PER_QUERY", env_file_values, "75")),
        gdelt_timespan=_get("GDELT_TIMESPAN", env_file_values, "7d"),
        gdelt_news_queries=tuple(
            query.strip()
            for query in _get(
                "GDELT_NEWS_QUERIES",
                env_file_values,
                "2026 FIFA World Cup,World Cup 2026 injury,World Cup 2026 suspension,World Cup 2026 squad,World Cup 2026 lineup",
            ).split(",")
            if query.strip()
        ),
        wikidata_api_url=_get(
            "WIKIDATA_API_URL",
            env_file_values,
            "https://www.wikidata.org/w/api.php",
        ),
        wikipedia_api_url=_get(
            "WIKIPEDIA_API_URL",
            env_file_values,
            "https://en.wikipedia.org/w/api.php",
        ),
    )
