# Current Model Data Status

Last refreshed: 2026-06-25T16:22:55.425145Z.

Refresh profile: `free-refresh`.

## Short Answer

The local refresh pipeline rebuilds the modeling database, metadata, diagnostics,
model outputs, and shareable Quarto reports. The public site presents summarized
results only; raw datasets and access files are kept out of the published site.

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
| --- | --- |
| `agg_news_query_counts_gdelt` | 11 |
| `agg_player_international_goals` | 15843 |
| `agg_team_elo_latest` | 336 |
| `agg_team_history` | 336 |
| `agg_team_recent_form` | 262 |
| `api_football_fixture_events` | 0 |
| `api_football_fixture_lineups` | 0 |
| `api_football_fixture_predictions` | 0 |
| `api_football_world_cup_fixtures` | 0 |
| `api_football_world_cup_injuries` | 0 |
| `api_football_world_cup_leagues` | 63 |
| `api_football_world_cup_odds` | 0 |
| `api_football_world_cup_players` | 0 |
| `api_football_world_cup_standings` | 0 |
| `api_football_world_cup_team_match_frame` | 0 |
| `api_football_world_cup_teams` | 0 |
| `dim_2026_world_cup_squad_players` | 1248 |
| `dim_locations_from_results` | 2214 |
| `dim_player_wikidata` | 1248 |
| `fact_2026_world_cup_fixture_times` | 72 |
| `fact_2026_world_cup_fixtures` | 72 |
| `fact_fixture_weather_hourly_open_meteo` | 1296 |
| `fact_international_matches_team_long` | 98954 |
| `fact_news_articles_gdelt` | 158 |
| `fact_player_goals` | 47747 |
| `fact_team_elo_match_history` | 98906 |
| `football_data_matches` | 0 |
| `odds_snapshots` | 0 |
| `raw_manifests` | 15 |
| `raw_snapshot_files` | 278 |
| `seed_venues` | 16 |
| `stg_international_goalscorers` | 47747 |
| `stg_international_results` | 49477 |
| `stg_international_shootouts` | 678 |
| `vw_2026_fixture_model_frame` | 72 |
| `vw_2026_squad_player_enriched` | 1248 |
| `vw_2026_squad_player_features` | 1248 |
| `vw_2026_team_model_features` | 48 |
| `vw_api_football_team_match_model_frame` | 0 |
| `vw_fixture_weather_signals` | 54 |
| `vw_goals_linear_model_frame` | 98810 |
| `vw_news_query_signals` | 11 |
| `vw_recent_team_form` | 262 |
| `vw_result_ordinal_model_frame` | 98810 |
| `vw_team_match_results` | 98954 |
| `weather_hourly` | 0 |

## Latest Raw Snapshot Sources

| Source | Status | Detail |
| --- | --- | --- |
| api-football | pulled | 200 |
| football-data | skipped | FOOTBALL_DATA_TOKEN is not set |
| odds | skipped | THE_ODDS_API_KEY is not set |
| official-fifa | pulled | 200 |
| public | pulled | 200 |
| wikimedia | pulled | 200 |

## Refresh Steps

| Step | Status | Seconds |
| --- | --- | --- |

## Public Artifacts Updated

- `docs\.nojekyll`

## Data Coverage Summary

| Area | Current role |
| --- | --- |
| Historical match results | Regression training data |
| Team strength history | Pre-match strength and opponent-strength features |
| 2026 fixtures and venues | Fixture scoring frame |
| Weather and news metadata | Context features and diagnostics |
| Football API enrichment | Coverage metadata now; richer match/player fields when populated |

## Planned Enrichment

The model is designed to add lineups, player availability, player-match statistics,
event detail, and market-implied probabilities as structured coverage expands.
