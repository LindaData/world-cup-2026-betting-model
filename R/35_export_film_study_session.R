# Export a per-match local film-study session bundle.
#
# In RStudio:
# source("R/35_export_film_study_session.R")
# export_film_study_session("wc2026-49483")

export_film_study_session <- function(match_key) {
  source("R/28_film_study_workflow.R", local = TRUE)
  run_python_script("scripts/export_film_study_session.py", c("--match-key", match_key))
  invisible(match_key)
}
