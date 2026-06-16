# Inventory the current DuckDB data store.
#
# Run from RStudio:
# source("R/06_data_inventory.R")

source("R/00_setup.R")

db_path <- file.path(here::here(), "data", "processed", "world_cup.duckdb")
drv <- duckdb::duckdb(dbdir = db_path, read_only = TRUE)
con <- DBI::dbConnect(drv)

cat("\nCore table counts\n")
print(DBI::dbGetQuery(con, "
  SELECT 'squad_players' AS table_name, COUNT(*) AS rows FROM dim_2026_world_cup_squad_players
  UNION ALL SELECT 'fixtures_2026', COUNT(*) FROM fact_2026_world_cup_fixtures
  UNION ALL SELECT 'team_match_long', COUNT(*) FROM fact_international_matches_team_long
  UNION ALL SELECT 'player_goals', COUNT(*) FROM fact_player_goals
  UNION ALL SELECT 'team_elo_match_history', COUNT(*) FROM fact_team_elo_match_history
  UNION ALL SELECT 'team_elo_latest', COUNT(*) FROM agg_team_elo_latest
  UNION ALL SELECT 'team_history', COUNT(*) FROM agg_team_history
  UNION ALL SELECT 'team_recent_form', COUNT(*) FROM agg_team_recent_form
  UNION ALL SELECT 'locations', COUNT(*) FROM dim_locations_from_results
  UNION ALL SELECT 'gdelt_news_articles', COUNT(*) FROM fact_news_articles_gdelt
"))

cat("\nSquad coverage by group\n")
print(DBI::dbGetQuery(con, "
  SELECT group_name, COUNT(DISTINCT team) AS teams, COUNT(*) AS players
  FROM dim_2026_world_cup_squad_players
  GROUP BY group_name
  ORDER BY group_name
"))

cat("\nFirst 8 fixture model rows\n")
print(DBI::dbGetQuery(con, "
  SELECT
    date,
    home_team,
    away_team,
    status,
    home_squad_caps_before_tournament,
    away_squad_caps_before_tournament,
    home_squad_goals_before_tournament,
    away_squad_goals_before_tournament,
    home_latest_elo,
    away_latest_elo,
    elo_diff_home_minus_away
  FROM vw_2026_fixture_model_frame
  ORDER BY date, source_match_id
  LIMIT 8
"))

cat("\nTop squad goal totals before tournament\n")
print(DBI::dbGetQuery(con, "
  SELECT
    team,
    latest_elo,
    squad_caps_before_tournament,
    squad_goals_before_tournament,
    avg_squad_age
  FROM vw_2026_team_model_features
  ORDER BY latest_elo DESC
  LIMIT 12
"))

DBI::dbDisconnect(con)
duckdb::duckdb_shutdown(drv)
