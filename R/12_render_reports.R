# Render the Quarto website.
#
# Run from RStudio:
# source("R/12_render_reports.R")

source("R/00_setup.R")

quarto_cache <- file.path(here::here(), ".quarto-deno")
quarto_appdata <- file.path(here::here(), ".localappdata")
dir.create(quarto_cache, recursive = TRUE, showWarnings = FALSE)
dir.create(quarto_appdata, recursive = TRUE, showWarnings = FALSE)
Sys.setenv(
  DENO_DIR = normalizePath(quarto_cache, winslash = "/", mustWork = TRUE),
  QUARTO_DENO_DIR = normalizePath(quarto_cache, winslash = "/", mustWork = TRUE),
  LOCALAPPDATA = normalizePath(quarto_appdata, winslash = "/", mustWork = TRUE),
  APPDATA = normalizePath(quarto_appdata, winslash = "/", mustWork = TRUE)
)

find_quarto <- function() {
  quarto_on_path <- Sys.which("quarto")
  if (nzchar(quarto_on_path)) {
    return(unname(quarto_on_path))
  }

  bundled <- "C:/Program Files/RStudio/resources/app/bin/quarto/bin/quarto.exe"
  if (file.exists(bundled)) {
    return(bundled)
  }

  stop("Quarto was not found. Install Quarto or open this project in a recent RStudio.")
}

quarto <- find_quarto()
message("Using Quarto: ", quarto)

result <- system2(quarto, args = c("render"), stdout = TRUE, stderr = TRUE)
cat(paste(result, collapse = "\n"), "\n")

status <- attr(result, "status")
if (!is.null(status) && status != 0) {
  stop("Quarto render failed with status ", status)
}

dir.create("docs", showWarnings = FALSE)
file.create(file.path("docs", ".nojekyll"))

message("Rendered Quarto site to docs/")
