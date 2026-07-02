# Build the local film-study video quality audit and render the private report.
#
# In RStudio:
# source("R/33_render_film_study_quality_report.R")
# render_film_study_quality_report()

render_film_study_quality_report <- function(
    input = "notebooks/film_study_quality.Rmd",
    output_dir = "data/private/reports") {

  if (!requireNamespace("rmarkdown", quietly = TRUE)) {
    stop("Package 'rmarkdown' is required. Install it with install.packages('rmarkdown').", call. = FALSE)
  }

  source("R/28_film_study_workflow.R", local = TRUE)
  build_video_quality_audit()

  if (!rmarkdown::pandoc_available()) {
    pandoc_candidates <- c(
      "C:/Program Files/RStudio/resources/app/bin/quarto/bin/tools",
      "C:/Program Files/RStudio/bin/pandoc"
    )
    existing <- pandoc_candidates[file.exists(file.path(pandoc_candidates, "pandoc.exe"))]
    if (length(existing) > 0) {
      Sys.setenv(RSTUDIO_PANDOC = existing[[1]])
    }
  }

  if (!rmarkdown::pandoc_available()) {
    stop("Pandoc is required and was not found. Install RStudio or Pandoc, then try again.", call. = FALSE)
  }

  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  data_dir <- normalizePath(file.path(getwd(), "data", "processed", "film_study"), winslash = "/", mustWork = TRUE)

  rendered <- rmarkdown::render(
    input = input,
    output_dir = normalizePath(output_dir, winslash = "/", mustWork = TRUE),
    params = list(data_dir = data_dir),
    envir = new.env(parent = globalenv()),
    quiet = TRUE
  )

  message("Rendered film-study quality report: ", rendered)
  invisible(rendered)
}
