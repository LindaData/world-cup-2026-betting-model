# One-command local film-study processing pipeline.
#
# In RStudio:
# source("R/34_process_film_study_session.R")
# process_film_study_session(
#   video = "C:/path/to/match.mp4",
#   match_key = "wc2026-49483",
#   home_team = "France",
#   away_team = "Sweden"
# )

process_film_study_session <- function(
    video = NULL,
    source_dir = NULL,
    match_key,
    home_team,
    away_team,
    competition = "World Cup 2026",
    kickoff_utc = NULL,
    skip_previews = FALSE,
    extract_clips = TRUE,
    clip_event_types = c("shot", "goal"),
    clip_seconds_before = 3,
    clip_seconds_after = 4,
    overwrite_clips = TRUE,
    skip_duckdb = FALSE,
    fit_models = TRUE,
    render_review_report = TRUE,
    render_quality_report = TRUE,
    render_modeling_report = TRUE) {

  source("R/28_film_study_workflow.R", local = TRUE)

  if (is.null(video) == is.null(source_dir)) {
    stop("Provide exactly one of 'video' or 'source_dir'.", call. = FALSE)
  }

  args <- c(
    "--match-key", match_key,
    "--home-team", home_team,
    "--away-team", away_team,
    "--competition", competition,
    "--clip-seconds-before", as.character(clip_seconds_before),
    "--clip-seconds-after", as.character(clip_seconds_after)
  )

  if (!is.null(video)) {
    args <- c(args, "--video", normalizePath(video, winslash = "/", mustWork = TRUE))
  } else {
    args <- c(args, "--source-dir", normalizePath(source_dir, winslash = "/", mustWork = TRUE))
  }

  if (!is.null(kickoff_utc) && nzchar(kickoff_utc)) {
    args <- c(args, "--kickoff-utc", kickoff_utc)
  }
  if (skip_previews) {
    args <- c(args, "--skip-previews")
  }
  if (extract_clips) {
    args <- c(args, "--extract-clips")
    if (!is.null(clip_event_types) && length(clip_event_types) > 0) {
      args <- c(args, "--clip-event-types", clip_event_types)
    }
  }
  if (overwrite_clips) {
    args <- c(args, "--overwrite-clips")
  }
  if (skip_duckdb) {
    args <- c(args, "--skip-duckdb")
  }
  if (fit_models) {
    args <- c(args, "--fit-models")
  }
  if (render_review_report) {
    args <- c(args, "--render-review-report")
  }
  if (render_quality_report) {
    args <- c(args, "--render-quality-report")
  }
  if (render_modeling_report) {
    args <- c(args, "--render-modeling-report")
  }

  run_python_script("scripts/process_film_study_session.py", args)
  invisible(0L)
}
