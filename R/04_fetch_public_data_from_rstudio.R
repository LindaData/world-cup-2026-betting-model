# Run Python raw-data pulls from inside RStudio.
#
# This uses cmd.exe because R 4.1.x on this Windows setup can call the venv
# reliably through cmd, while direct system2() calls to the venv Python fail.

source("R/00_setup.R")

venv_python <- file.path(here::here(), ".venv", "Scripts", "python.exe")

if (!file.exists(venv_python)) {
  stop("Project venv not found. Create it first with: python -m venv .venv")
}

command <- "cmd /c .venv\\Scripts\\python.exe scripts\\fetch_raw_data.py --sources public"
message("Running: ", command)
output <- system(command, intern = TRUE)
cat(paste(output, collapse = "\n"), "\n")

message("Rebuilding DuckDB from the latest raw snapshot...")
source("R/01_build_duckdb.R")

