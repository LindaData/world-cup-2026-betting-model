# Check readiness for RStudio, Shiny, Streamlit, and the shared DuckDB backend.
#
# Run from RStudio:
# source("R/05_check_app_readiness.R")

source("R/00_setup.R")

check_packages <- function(packages) {
  data.frame(
    package = packages,
    installed = vapply(packages, requireNamespace, logical(1), quietly = TRUE),
    version = vapply(
      packages,
      function(package) {
        if (requireNamespace(package, quietly = TRUE)) {
          as.character(utils::packageVersion(package))
        } else {
          NA_character_
        }
      },
      character(1)
    ),
    stringsAsFactors = FALSE
  )
}

cat("\nR environment\n")
cat("R version: ", R.version.string, "\n", sep = "")
cat("R home: ", R.home(), "\n", sep = "")
cat("Project root: ", here::here(), "\n", sep = "")
cat("R libraries:\n")
cat(paste(" -", .libPaths()), sep = "\n")
cat("\n")

cat("\nR packages for Shiny app work\n")
print(check_packages(c(
  "shiny",
  "bslib",
  "DT",
  "plotly",
  "ggplot2",
  "dplyr",
  "readr",
  "DBI",
  "duckdb",
  "rsconnect"
)))

cat("\nR packages for modeling candidates\n")
print(check_packages(c(
  "MASS",
  "ordinal",
  "VGAM",
  "tidymodels",
  "brms",
  "cmdstanr"
)))

db_path <- file.path(here::here(), "data", "processed", "world_cup.duckdb")
cat("\nDuckDB database\n")
cat("Path: ", db_path, "\n", sep = "")
cat("Exists: ", file.exists(db_path), "\n", sep = "")

if (file.exists(db_path)) {
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = db_path, read_only = TRUE)
  print(DBI::dbGetQuery(con, "SELECT COUNT(*) AS venues FROM seed_venues"))
  DBI::dbDisconnect(con, shutdown = TRUE)
}

venv_python <- file.path(here::here(), ".venv", "Scripts", "python.exe")
cat("\nPython / Streamlit readiness\n")
cat("Project venv Python: ", venv_python, "\n", sep = "")
cat("Exists: ", file.exists(venv_python), "\n", sep = "")

if (file.exists(venv_python)) {
  command <- paste(
    "cmd /c .venv\\Scripts\\python.exe -c",
    shQuote(
      "import importlib.util; mods=['streamlit','duckdb','pandas','plotly','altair','sklearn']; print({m: importlib.util.find_spec(m) is not None for m in mods})"
    )
  )
  print(system(command, intern = TRUE))
}

cat("\nRecommendation\n")
cat("- Shiny is the lower-friction first app path on this machine.\n")
cat("- Streamlit is also viable after installing Python app packages into .venv.\n")
cat("- Keep DuckDB as the shared data backend for both app options.\n")

