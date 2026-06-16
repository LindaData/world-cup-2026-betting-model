# Data Inventory

Last built: 2026-06-16.

## Raw Snapshot

Latest raw snapshot:

```text
data/raw/20260616T162629Z
```

It contains:

- `international_results.csv`
- `international_goalscorers.csv`
- `international_shootouts.csv`
- `openfootball_cup.txt`
- `openfootball_stadiums.csv`
- `wikimedia_2026_fifa_world_cup.json`
- `wikimedia_2026_fifa_world_cup.wikitext`
- `wikimedia_2026_fifa_world_cup_squads.json`
- `wikimedia_2026_fifa_world_cup_squads.wikitext`
- `wikimedia_2026_fifa_world_cup_officials.json`
- `wikimedia_2026_fifa_world_cup_officials.wikitext`
- `fifa_2026_squad_list.pdf`
- `manifest.json`

## Processed CSVs

Processed CSVs are generated under:

```text
data/processed/public_csv
```

Current generated tables:

| File | Rows | Meaning |
| --- | ---: | --- |
| `dim_2026_world_cup_squad_players.csv` | 1,248 | 48 squads x 26 players, with position, age, caps, goals, club |
| `fact_2026_world_cup_fixtures.csv` | 72 | 2026 World Cup fixtures/results from public results data |
| `fact_international_matches_team_long.csv` | 98,954 | Historical team-match rows, one row per team per match |
| `fact_player_goals.csv` | 47,647 | Historical international goal events |
| `agg_player_international_goals.csv` | 15,821 | Goal totals by player/team from the public goal-event dataset |
| `agg_team_history.csv` | 336 | All-time team aggregates from public results |
| `agg_team_recent_form.csv` | 262 | Team aggregates since 2022-01-01 |
| `fact_team_elo_match_history.csv` | 98,842 | Pre/post Elo row per team per rated historical match |
| `agg_team_elo_latest.csv` | 336 | Latest calculated team Elo ratings |
| `dim_locations_from_results.csv` | 2,214 | Match locations appearing in historical results |

## DuckDB

Main database:

```text
data/processed/world_cup.duckdb
```

Useful model-facing views:

- `vw_2026_fixture_model_frame`
- `vw_2026_team_model_features`
- `vw_2026_squad_player_features`
- `vw_team_match_results`
- `vw_recent_team_form`

Inspect from RStudio:

```r
source("R/06_data_inventory.R")
```

## Current Public Data Limits

Public/no-key sources give us:

- Team match results.
- Team scoring and conceded history.
- Goal events by player.
- Squad player list with pre-tournament caps/goals.
- Club and position for squad players.
- Tournament fixtures/results.
- Host venue seed data.
- A computed Elo baseline.

Public/no-key sources do not yet give us complete:

- Player appearances by match.
- Player minutes.
- Lineups and substitutions.
- Cards, shots, xG, assists, goalkeeper saves, or detailed player match statistics.
- Real-time injuries/suspensions.
- Odds snapshots.

Those likely require API keys, especially API-Football and The Odds API.

