# Current Data Status

Last checked: 2026-06-16.

## Short Answer

All no-key/free public sources currently wired in the project have been pulled and stored, except that the GDELT news pull should be treated as a partial/test pull.

APIs that have free tiers but require your personal API key are wired but not pulled:

- football-data.org
- The Odds API
- API-Football

## Stored In DuckDB

Database:

```text
data/processed/world_cup.duckdb
```

Metadata exports:

```text
data/processed/metadata/table_inventory.csv
data/processed/metadata/column_inventory.csv
```

## Table Counts

| Table/View | Rows |
| --- | ---: |
| `dim_2026_world_cup_squad_players` | 1,248 |
| `dim_player_wikidata` | 1,248 |
| `fact_2026_world_cup_fixtures` | 72 |
| `fact_fixture_weather_hourly_open_meteo` | 480 |
| `fact_international_matches_team_long` | 98,954 |
| `fact_player_goals` | 47,647 |
| `fact_team_elo_match_history` | 98,842 |
| `fact_news_articles_gdelt` | 172 |
| `agg_news_query_counts_gdelt` | 8 |
| `agg_player_international_goals` | 15,821 |
| `agg_team_elo_latest` | 336 |
| `agg_team_history` | 336 |
| `agg_team_recent_form` | 262 |
| `dim_locations_from_results` | 2,214 |
| `seed_venues` | 16 |
| `vw_2026_fixture_model_frame` | 72 |
| `vw_2026_squad_player_enriched` | 1,248 |
| `vw_2026_team_model_features` | 48 |
| `vw_fixture_weather_signals` | 20 |
| `vw_news_query_signals` | 8 |

## Connected And Pulled

| Source | Key needed | Status |
| --- | --- | --- |
| martj42 international results | No | Pulled |
| Openfootball World Cup files | No | Pulled |
| Wikimedia squad/World Cup pages | No | Pulled |
| Wikidata player metadata | No | Pulled |
| Official FIFA squad PDF | No | Pulled raw |
| Open-Meteo weather | No | Pulled for mapped fixtures |
| GDELT news metadata | No | Partial/test pull stored |

## Wired But Waiting For Your Key

| Source | Key needed | What it adds |
| --- | --- | --- |
| football-data.org | Yes | Fixtures, standings, scorers, squads depending on plan |
| The Odds API | Yes | Odds snapshots, market probabilities, historical odds on paid tier |
| API-Football | Yes | Lineups, injuries, events, player stats, odds, predictions |

## Known Missing Model Inputs

These are not fully available from current no-key sources:

- Confirmed starting lineups.
- Substitutions and minutes played.
- Player-match statistics.
- Injuries and suspensions.
- Cards, shots, possession, saves, xG.
- Odds movement and closing lines.
- Complete player identity enrichment for every squad player.

