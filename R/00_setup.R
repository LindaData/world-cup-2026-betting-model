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
  # Respect preconfigured repos (e.g. Posit Package Manager binaries on CI,
  # set by r-lib/actions with use-public-rspm) instead of forcing source
  # builds from CRAN; fall back to CRAN when nothing is configured.
  repos <- getOption("repos")
  if (is.null(repos) || !nzchar(repos[[1]]) || identical(unname(repos[[1]]), "@CRAN@")) {
    repos <- c(CRAN = "https://cloud.r-project.org")
  }
  install.packages(missing_packages, repos = repos)
  still_missing <- missing_packages[!vapply(missing_packages, requireNamespace, logical(1), quietly = TRUE)]
  if (length(still_missing) > 0) {
    stop("R packages failed to install: ", paste(still_missing, collapse = ", "))
  }
}

invisible(lapply(required_packages, library, character.only = TRUE))

message("R setup complete.")
message("Project root: ", here::here())
message("Project R library: ", project_library)
