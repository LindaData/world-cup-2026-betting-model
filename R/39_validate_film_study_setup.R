# Validate that the local film-study capture workflow is ready on this laptop.
#
# In RStudio:
# source("R/39_validate_film_study_setup.R")
# validate_local_film_study_setup()

validate_local_film_study_setup <- function() {
  source("R/28_film_study_workflow.R", local = TRUE)
  result <- validate_film_study_setup()

  summary <- list(
    overall_ok = isTRUE(result$overall_ok),
    monitor_count = if (!is.null(result$monitors$monitor_count)) result$monitors$monitor_count else 0L,
    import_status = vapply(result$imports, function(x) isTRUE(x$ok), logical(1)),
    directories_ok = vapply(result$directories, function(x) isTRUE(x$exists) && isTRUE(x$is_dir), logical(1)),
    files_ok = vapply(result$files, function(x) isTRUE(x$exists), logical(1)),
    raw = result
  )

  class(summary) <- c("film_study_setup_summary", class(summary))
  summary
}

print.film_study_setup_summary <- function(x, ...) {
  cat("Film Study Setup\n")
  cat("overall_ok:", x$overall_ok, "\n")
  cat("monitor_count:", x$monitor_count, "\n")
  cat("imports_ok:", paste(names(x$import_status)[x$import_status], collapse = ", "), "\n")
  invisible(x)
}
