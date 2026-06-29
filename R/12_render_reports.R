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

status_doc <- file.path("docs", "current_data_status.md")
status_doc_backup <- tempfile(fileext = ".md")
has_status_doc <- file.exists(status_doc)
if (has_status_doc) {
  file.copy(status_doc, status_doc_backup, overwrite = TRUE)
}

result <- system2(quarto, args = c("render"), stdout = TRUE, stderr = TRUE)
cat(paste(result, collapse = "\n"), "\n")

status <- attr(result, "status")
if (!is.null(status) && status != 0) {
  stop("Quarto render failed with status ", status)
}

dir.create("docs", showWarnings = FALSE)
file.create(file.path("docs", ".nojekyll"))
if (has_status_doc && file.exists(status_doc_backup)) {
  file.copy(status_doc_backup, status_doc, overwrite = TRUE)
}
static_docs <- c(
  file.path("docs_static", "GITHUB_ACCOUNT_UX_REVIEW.md")
)
for (static_doc in static_docs[file.exists(static_docs)]) {
  file.copy(static_doc, file.path("docs", basename(static_doc)), overwrite = TRUE)
}

message("Rendered Quarto site to docs/")
