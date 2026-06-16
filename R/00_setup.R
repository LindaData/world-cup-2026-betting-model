# RStudio setup for the World Cup betting data project.
#
# Run this from the project root:
# source("R/00_setup.R")

required_packages <- c(
  "DBI",
  "duckdb",
  "dplyr",
  "readr",
  "jsonlite",
  "glue",
  "here",
  "reticulate"
)

project_library <- file.path(getwd(), ".r-lib", paste0(R.version$major, ".", R.version$minor))
dir.create(project_library, recursive = TRUE, showWarnings = FALSE)
.libPaths(c(project_library, .libPaths()))

missing_packages <- required_packages[!vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)]

if (length(missing_packages) > 0) {
  message("Installing missing R packages: ", paste(missing_packages, collapse = ", "))
  install.packages(missing_packages, repos = "https://cloud.r-project.org")
}

invisible(lapply(required_packages, library, character.only = TRUE))

message("R setup complete.")
message("Project root: ", here::here())
message("Project R library: ", project_library)
