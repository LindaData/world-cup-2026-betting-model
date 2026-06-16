# First SQL queries from R.
#
# Run after R/01_build_duckdb.R has created data/processed/world_cup.duckdb.

source("R/00_setup.R")

db_path <- file.path(here::here(), "data", "processed", "world_cup.duckdb")
drv <- duckdb::duckdb(dbdir = db_path, read_only = TRUE)
con <- DBI::dbConnect(drv)
closed_connection <- FALSE
close_duckdb <- function() {
  if (!closed_connection) {
    if (DBI::dbIsValid(con)) {
      DBI::dbDisconnect(con)
    }
    duckdb::duckdb_shutdown(drv)
    closed_connection <<- TRUE
  }
}
on.exit(close_duckdb(), add = TRUE)

cat("\nVenues by region:\n")
print(DBI::dbGetQuery(con, "
  SELECT region, COUNT(*) AS venues, SUM(capacity) AS total_capacity
  FROM seed_venues
  GROUP BY region
  ORDER BY region
"))

if ("stg_international_results" %in% DBI::dbListTables(con)) {
  cat("\nRecent World Cup matches in historical results dataset:\n")
  print(DBI::dbGetQuery(con, "
    SELECT date, home_team, away_team, home_score, away_score, tournament
    FROM stg_international_results
    WHERE tournament = 'FIFA World Cup'
    ORDER BY date DESC
    LIMIT 10
  "))
}

DBI::dbDisconnect(con)
duckdb::duckdb_shutdown(drv)
closed_connection <- TRUE
