# Record a local screen region, open the tagger, then rebuild private outputs.
#
# In RStudio:
# source("R/38_capture_and_process_film_study_session.R")
# capture_and_process_film_study_session(
#   match_key = "wc2026-49483",
#   home_team = "France",
#   away_team = "Sweden"
# )

capture_and_process_film_study_session <- function(
    match_key,
    home_team,
    away_team,
    competition = "World Cup 2026",
    kickoff_utc = NULL,
    monitor = 1,
    region = NULL,
    select_region = TRUE,
    mock_video = NULL,
    profile_name = NULL,
    save_profile = FALSE,
    fps = 30,
    quality_profile = c("archive", "compact"),
    max_seconds = 0,
    no_preview = FALSE,
    window_scale = 0.6,
    create_preset_template = TRUE,
    launch_tagger = TRUE,
    skip_previews = FALSE,
    extract_clips = TRUE,
    clip_event_types = c("shot", "goal"),
    clip_seconds_before = 3,
    clip_seconds_after = 4,
    overwrite_clips = TRUE,
    build_duckdb = TRUE,
    fit_models = TRUE,
    fit_state_engine = TRUE,
    export_session_bundle = TRUE,
    render_review_report = TRUE,
    render_quality_report = TRUE,
    render_modeling_report = TRUE,
    render_state_engine_report = TRUE) {

  quality_profile <- match.arg(quality_profile)

  source("R/28_film_study_workflow.R", local = TRUE)
  source("R/29_render_film_study_review.R", local = TRUE)
  source("R/31_fit_film_study_models.R", local = TRUE)
  source("R/32_render_film_study_modeling_report.R", local = TRUE)
  source("R/33_render_film_study_quality_report.R", local = TRUE)
  source("R/35_export_film_study_session.R", local = TRUE)
  source("R/36_fit_film_study_state_engine.R", local = TRUE)
  source("R/37_render_film_study_state_engine_report.R", local = TRUE)

  if (create_preset_template) {
    create_tagger_preset_template(
      match_key = match_key,
      home_team = home_team,
      away_team = away_team
    )
  }

  capture_film_study_screen(
    match_key = match_key,
    home_team = home_team,
    away_team = away_team,
    competition = competition,
    kickoff_utc = kickoff_utc,
    monitor = monitor,
    region = region,
    select_region = select_region,
    mock_video = mock_video,
    profile_name = profile_name,
    save_profile = save_profile,
    fps = fps,
    quality_profile = quality_profile,
    max_seconds = max_seconds,
    no_preview = no_preview,
    window_scale = window_scale,
    launch_tagger = launch_tagger,
    skip_previews = skip_previews
  )

  refresh_film_study_analysis_bundle(
    extract_clips = extract_clips,
    clip_event_types = clip_event_types,
    clip_seconds_before = clip_seconds_before,
    clip_seconds_after = clip_seconds_after,
    overwrite_clips = overwrite_clips,
    build_duckdb = build_duckdb
  )

  if (fit_models) {
    fit_film_study_models()
  }
  if (fit_state_engine) {
    fit_film_study_state_engine()
  }
  if (export_session_bundle) {
    export_film_study_session(match_key)
    build_film_study_session_index()
  }
  if (render_review_report) {
    render_film_study_review()
  }
  if (render_quality_report) {
    render_film_study_quality_report()
  }
  if (render_modeling_report) {
    render_film_study_modeling_report()
  }
  if (render_state_engine_report) {
    render_film_study_state_engine_report()
  }

  outputs <- list(
    catalog_csv = file.path(getwd(), "data", "private", "video_library", "video_catalog.csv"),
    tags_dir = file.path(getwd(), "data", "private", "film_tags"),
    processed_dir = file.path(getwd(), "data", "processed", "film_study"),
    session_export_dir = file.path(getwd(), "data", "private", "session_exports", match_key),
    review_report = file.path(getwd(), "data", "private", "reports", "film_study_review.html"),
    quality_report = file.path(getwd(), "data", "private", "reports", "film_study_quality.html"),
    modeling_report = file.path(getwd(), "data", "private", "reports", "film_study_modeling.html"),
    state_engine_report = file.path(getwd(), "data", "private", "reports", "film_study_state_engine.html")
  )

  invisible(outputs)
}
