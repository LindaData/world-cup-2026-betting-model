# Current Data Status

Last refreshed: 2026-06-16T22:59:46.970308Z.

Refresh profile: `local-rebuild`.

Local run folder:

```text
data\processed\update_runs\20260616T225946Z
```

## Short Answer

The local refresh pipeline is now the source of truth for this project. It can rebuild from
existing local files or pull free/no-key public sources, then rebuild DuckDB, metadata,
model outputs, and shareable report artifacts.

APIs that have free tiers but require your personal API key are wired but only run when keys
are added to `.env` and the updater is called with `--include-keyed-apis`.

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
| `agg_news_query_counts_gdelt` | 8 |
| `agg_player_international_goals` | 15821 |
| `agg_team_elo_latest` | 336 |
| `agg_team_history` | 336 |
| `agg_team_recent_form` | 262 |
| `dim_2026_world_cup_squad_players` | 1248 |
| `dim_locations_from_results` | 2214 |
| `dim_player_wikidata` | 1248 |
| `fact_2026_world_cup_fixtures` | 72 |
| `fact_fixture_weather_hourly_open_meteo` | 480 |
| `fact_international_matches_team_long` | 98954 |
| `fact_news_articles_gdelt` | 172 |
| `fact_player_goals` | 47647 |
| `fact_team_elo_match_history` | 98842 |
| `football_data_matches` | 0 |
| `odds_snapshots` | 0 |
| `raw_manifests` | 2 |
| `raw_snapshot_files` | 19 |
| `seed_venues` | 16 |
| `stg_international_goalscorers` | 47647 |
| `stg_international_results` | 49477 |
| `stg_international_shootouts` | 678 |
| `vw_2026_fixture_model_frame` | 72 |
| `vw_2026_squad_player_enriched` | 1248 |
| `vw_2026_squad_player_features` | 1248 |
| `vw_2026_team_model_features` | 48 |
| `vw_fixture_weather_signals` | 20 |
| `vw_goals_linear_model_frame` | 98810 |
| `vw_news_query_signals` | 8 |
| `vw_recent_team_form` | 262 |
| `vw_result_ordinal_model_frame` | 98810 |
| `vw_team_match_results` | 98954 |
| `weather_hourly` | 0 |

## Latest Raw Snapshot Sources

| Source | Status | Detail |
| --- | --- | --- |
| official-fifa | pulled | 200 |
| public | pulled | 200 |
| wikimedia | pulled | 200 |

## Refresh Steps

| Step | Status | Seconds |
| --- | --- | --- |
| Build processed public CSVs | ok | 14.231 |
| Build DuckDB | ok | 11.005 |
| Export DuckDB metadata | ok | 3.903 |
| Fit baseline goals model | ok | 6.634 |
| Fit ordinal result model | ok | 12.219 |
| Render R Markdown reports | ok | 10.599 |

## Public Artifacts Updated

- `data\samples\goals_linear_model_sample_1000.csv`
- `docs\samples\goals_linear_model_sample_1000.csv`
- `data\samples\result_ordinal_model_sample_1000.csv`
- `docs\samples\result_ordinal_model_sample_1000.csv`
- `docs\reports\01_goals_linear_regression.html`
- `docs\reports\02_ordinal_result_model.html`

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
