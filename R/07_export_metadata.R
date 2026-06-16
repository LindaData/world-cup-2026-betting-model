# Export table/column metadata from DuckDB for review.
#
# Run from RStudio:
# source("R/07_export_metadata.R")

source("R/00_setup.R")

db_path <- file.path(here::here(), "data", "processed", "world_cup.duckdb")
metadata_dir <- file.path(here::here(), "data", "processed", "metadata")
dir.create(metadata_dir, recursive = TRUE, showWarnings = FALSE)

drv <- duckdb::duckdb(dbdir = db_path, read_only = TRUE)
con <- DBI::dbConnect(drv)

tables <- DBI::dbListTables(con)

table_rows <- lapply(tables, function(table_name) {
  count <- DBI::dbGetQuery(con, paste0("SELECT COUNT(*) AS n FROM ", table_name))$n[[1]]
  data.frame(table_name = table_name, row_count = count, stringsAsFactors = FALSE)
})
table_inventory <- do.call(rbind, table_rows)

column_rows <- lapply(tables, function(table_name) {
  fields <- DBI::dbGetQuery(con, paste0("DESCRIBE ", table_name))
  data.frame(
    table_name = table_name,
    column_name = fields$column_name,
    column_type = fields$column_type,
    nullable = fields$null,
    stringsAsFactors = FALSE
  )
})
column_inventory <- do.call(rbind, column_rows)

field_catalog_path <- file.path(here::here(), "docs", "field_catalog.csv")
if (file.exists(field_catalog_path)) {
  field_catalog <- readr::read_csv(field_catalog_path, show_col_types = FALSE)
  column_inventory <- dplyr::left_join(
    column_inventory,
    field_catalog,
    by = c("table_name", "column_name")
  )
}

readr::write_csv(table_inventory, file.path(metadata_dir, "table_inventory.csv"))
readr::write_csv(column_inventory, file.path(metadata_dir, "column_inventory.csv"))

cat("\nTable inventory written to:\n", file.path(metadata_dir, "table_inventory.csv"), "\n", sep = "")
cat("Column inventory written to:\n", file.path(metadata_dir, "column_inventory.csv"), "\n", sep = "")

print(table_inventory[order(table_inventory$table_name), ])

DBI::dbDisconnect(con)
duckdb::duckdb_shutdown(drv)

