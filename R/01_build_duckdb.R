# Build/update the local DuckDB database from seed data and latest raw snapshot.
#
# Run this after fetching raw files:
# source("R/01_build_duckdb.R")

source("R/00_setup.R")

project_root <- here::here()
db_path <- file.path(project_root, "data", "processed", "world_cup.duckdb")
seed_venues_path <- file.path(project_root, "data", "seed", "venues_2026_world_cup.csv")
raw_root <- file.path(project_root, "data", "raw")
processed_csv_root <- file.path(project_root, "data", "processed", "public_csv")

dir.create(dirname(db_path), recursive = TRUE, showWarnings = FALSE)

drv <- duckdb::duckdb(dbdir = db_path)
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

execute_sql_file <- function(con, path) {
  sql <- paste(readLines(path, warn = FALSE), collapse = "\n")
  statements <- trimws(strsplit(sql, ";", fixed = TRUE)[[1]])
  statements <- statements[nzchar(statements)]
  for (statement in statements) {
    DBI::dbExecute(con, statement)
  }
  invisible(TRUE)
}

execute_sql_file(con, "sql/schema.sql")

venues <- readr::read_csv(seed_venues_path, show_col_types = FALSE)
DBI::dbWriteTable(con, "seed_venues", venues, overwrite = TRUE)

processed_csv_files <- list.files(processed_csv_root, pattern = "\\.csv$", full.names = TRUE)
if (length(processed_csv_files) > 0) {
  for (csv_file in processed_csv_files) {
    table_name <- tools::file_path_sans_ext(basename(csv_file))
    message("Loading processed CSV table: ", table_name)
    data <- readr::read_csv(csv_file, show_col_types = FALSE)
    DBI::dbWriteTable(con, table_name, data, overwrite = TRUE)
  }
} else {
  message("No processed CSV files found yet. Run: .venv\\Scripts\\python.exe scripts\\build_public_processed_csv.py")
}

snapshot_dirs <- list.dirs(raw_root, recursive = FALSE, full.names = TRUE)
snapshot_dirs <- snapshot_dirs[file.exists(file.path(snapshot_dirs, "manifest.json"))]

if (length(snapshot_dirs) == 0) {
  message("No raw snapshots found yet. Run: python scripts\\fetch_raw_data.py --sources public")
} else {
  latest_snapshot <- snapshot_dirs[which.max(file.info(snapshot_dirs)$mtime)]
  message("Loading latest raw snapshot: ", latest_snapshot)

  manifest_path <- file.path(latest_snapshot, "manifest.json")
  manifest <- jsonlite::fromJSON(manifest_path, simplifyVector = FALSE)

  files <- list.files(latest_snapshot, full.names = TRUE)
  file_index <- data.frame(
    snapshot_id = basename(latest_snapshot),
    file_name = basename(files),
    file_path = normalizePath(files, winslash = "/", mustWork = FALSE),
    file_ext = tools::file_ext(files),
    bytes = file.info(files)$size,
    modified_at = as.character(file.info(files)$mtime),
    stringsAsFactors = FALSE
  )

  DBI::dbExecute(
    con,
    "DELETE FROM raw_snapshot_files WHERE snapshot_id = ?",
    params = list(basename(latest_snapshot))
  )
  DBI::dbWriteTable(con, "raw_snapshot_files", file_index, append = TRUE)

  results_path <- file.path(latest_snapshot, "international_results.csv")
  if (file.exists(results_path)) {
    results <- readr::read_csv(results_path, show_col_types = FALSE)
    DBI::dbWriteTable(con, "stg_international_results", results, overwrite = TRUE)
  }

  goalscorers_path <- file.path(latest_snapshot, "international_goalscorers.csv")
  if (file.exists(goalscorers_path)) {
    goalscorers <- readr::read_csv(goalscorers_path, show_col_types = FALSE)
    DBI::dbWriteTable(con, "stg_international_goalscorers", goalscorers, overwrite = TRUE)
  }

  shootouts_path <- file.path(latest_snapshot, "international_shootouts.csv")
  if (file.exists(shootouts_path)) {
    shootouts <- readr::read_csv(shootouts_path, show_col_types = FALSE)
    DBI::dbWriteTable(con, "stg_international_shootouts", shootouts, overwrite = TRUE)
  }

  DBI::dbExecute(
    con,
    "DELETE FROM raw_manifests WHERE snapshot_id = ?",
    params = list(basename(latest_snapshot))
  )
  DBI::dbWriteTable(
    con,
    "raw_manifests",
    data.frame(
      snapshot_id = basename(latest_snapshot),
      manifest_json = as.character(jsonlite::toJSON(manifest, auto_unbox = TRUE)),
      stringsAsFactors = FALSE
    ),
    append = TRUE
  )
}

view_files <- sort(list.files("sql/views", pattern = "\\.sql$", full.names = TRUE))
for (view_file in view_files) {
  execute_sql_file(con, view_file)
}

message("DuckDB ready: ", db_path)
message("Tables:")
print(DBI::dbListTables(con))

DBI::dbDisconnect(con)
duckdb::duckdb_shutdown(drv)
closed_connection <- TRUE
