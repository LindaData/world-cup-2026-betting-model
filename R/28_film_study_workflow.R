# Local film-study workflow helpers for RStudio.
#
# In RStudio:
# source("R/28_film_study_workflow.R")
# prepare_film_session(
#   video = "C:/path/to/match.mp4",
#   match_key = "wc2026-49483",
#   home_team = "France",
#   away_team = "Sweden"
# )

project_python <- function() {
  candidates <- c(
    file.path(getwd(), ".venv", "Scripts", "python.exe"),
    Sys.which("python")
  )
  candidates <- candidates[nzchar(candidates)]
  existing <- candidates[file.exists(candidates)]
  if (length(existing) > 0) {
    return(normalizePath(existing[[1]], winslash = "/", mustWork = TRUE))
  }
  stop("Could not find Python. Expected .venv/Scripts/python.exe or python on PATH.")
}

run_python_script <- function(script, args = character()) {
  powershell <- Sys.getenv("SystemRoot", unset = "C:/Windows")
  powershell <- file.path(powershell, "System32", "WindowsPowerShell", "v1.0", "powershell.exe")
  if (!file.exists(powershell)) {
    stop("Could not find powershell.exe for the local Python bridge.", call. = FALSE)
  }

  command <- paste(
    c(
      shQuote(powershell),
      "-ExecutionPolicy", "Bypass",
      "-File", shQuote("scripts/run_project_python.ps1"),
      shQuote(script),
      shQuote(args)
    ),
    collapse = " "
  )
  exit_code <- system(command, intern = FALSE, ignore.stdout = FALSE, ignore.stderr = FALSE)

  if (!identical(exit_code, 0L)) {
    stop("Python command failed for ", script, " with exit code ", exit_code, call. = FALSE)
  }

  invisible(exit_code)
}

run_python_script_output <- function(script, args = character()) {
  powershell <- Sys.getenv("SystemRoot", unset = "C:/Windows")
  powershell <- file.path(powershell, "System32", "WindowsPowerShell", "v1.0", "powershell.exe")
  if (!file.exists(powershell)) {
    stop("Could not find powershell.exe for the local Python bridge.", call. = FALSE)
  }

  command <- paste(
    c(
      shQuote(powershell),
      "-ExecutionPolicy", "Bypass",
      "-File", shQuote("scripts/run_project_python.ps1"),
      shQuote(script),
      shQuote(args)
    ),
    collapse = " "
  )
  output <- system(command, intern = TRUE, ignore.stderr = FALSE)
  invisible(output)
}

prepare_film_session <- function(
    video,
    match_key,
    home_team,
    away_team,
    competition = "World Cup 2026",
    kickoff_utc = NULL,
    launch_tagger = FALSE,
    skip_previews = FALSE) {

  args <- c(
    "--video", normalizePath(video, winslash = "/", mustWork = TRUE),
    "--match-key", match_key,
    "--home-team", home_team,
    "--away-team", away_team,
    "--competition", competition
  )

  if (!is.null(kickoff_utc) && nzchar(kickoff_utc)) {
    args <- c(args, "--kickoff-utc", kickoff_utc)
  }
  if (launch_tagger) {
    args <- c(args, "--launch-tagger")
  }
  if (skip_previews) {
    args <- c(args, "--skip-previews")
  }

  run_python_script("scripts/prepare_film_study_session.py", args)
}

launch_film_tagger <- function(
    video,
    match_key,
    home_team,
    away_team,
    scale_width = 1280,
    start_playing = FALSE) {

  args <- c(
    "--video", normalizePath(video, winslash = "/", mustWork = TRUE),
    "--match-key", match_key,
    "--home-team", home_team,
    "--away-team", away_team,
    "--scale-width", as.character(scale_width)
  )

  if (start_playing) {
    args <- c(args, "--start-playing")
  }

  run_python_script("scripts/video_tagger.py", args)
}

build_film_study_dataset <- function() {
  run_python_script("scripts/build_film_study_dataset.py")
}

build_film_study_features <- function() {
  run_python_script("scripts/build_film_study_features.py")
}

list_capture_monitors <- function() {
  output <- run_python_script_output("scripts/capture_film_study_screen.py", c("--list-monitors"))
  jsonlite::fromJSON(paste(output, collapse = "\n"), simplifyDataFrame = TRUE)
}

create_tagger_preset_template <- function(match_key, home_team, away_team) {
  args <- c(
    "--match-key", match_key,
    "--home-team", home_team,
    "--away-team", away_team
  )
  run_python_script("scripts/create_tagger_preset_template.py", args)
}

list_capture_profiles <- function() {
  profiles_dir <- file.path(getwd(), "data", "private", "capture_profiles")
  if (!dir.exists(profiles_dir)) {
    return(data.frame())
  }

  files <- list.files(profiles_dir, pattern = "\\.json$", full.names = TRUE)
  if (length(files) == 0) {
    return(data.frame())
  }

  rows <- lapply(files, function(path) {
    payload <- jsonlite::fromJSON(path, simplifyVector = TRUE)
    data.frame(
      profile_name = if (!is.null(payload$profile_name)) as.character(payload$profile_name) else tools::file_path_sans_ext(basename(path)),
      left = if (!is.null(payload$left)) as.integer(payload$left) else NA_integer_,
      top = if (!is.null(payload$top)) as.integer(payload$top) else NA_integer_,
      width = if (!is.null(payload$width)) as.integer(payload$width) else NA_integer_,
      height = if (!is.null(payload$height)) as.integer(payload$height) else NA_integer_,
      monitor = if (!is.null(payload$monitor)) as.integer(payload$monitor) else NA_integer_,
      saved_at_utc = if (!is.null(payload$saved_at_utc)) as.character(payload$saved_at_utc) else "",
      profile_path = normalizePath(path, winslash = "/", mustWork = TRUE),
      stringsAsFactors = FALSE
    )
  })

  dplyr::bind_rows(rows) |>
    dplyr::arrange(dplyr::desc(.data$saved_at_utc), .data$profile_name)
}

create_capture_profile <- function(
    profile_name,
    monitor = 1,
    region = NULL,
    select_region = TRUE) {

  args <- c(
    "--match-key", "profile-setup",
    "--home-team", "Home",
    "--away-team", "Away",
    "--monitor", as.character(monitor),
    "--profile-name", profile_name,
    "--save-profile",
    "--save-profile-only"
  )

  if (!is.null(region)) {
    if (length(region) != 4) {
      stop("region must contain left, top, width, and height.", call. = FALSE)
    }
    args <- c(args, "--region", as.character(region))
  } else if (select_region) {
    args <- c(args, "--select-region")
  }

  run_python_script("scripts/capture_film_study_screen.py", args)
}

validate_film_study_setup <- function() {
  output <- run_python_script_output("scripts/validate_film_study_setup.py")
  payload <- output[!grepl("^Wrote ", output)]
  jsonlite::fromJSON(paste(payload, collapse = "\n"), simplifyVector = TRUE)
}

capture_film_study_screen <- function(
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
    launch_tagger = FALSE,
    skip_previews = FALSE,
    no_preview = FALSE,
    window_scale = 0.6) {

  quality_profile <- match.arg(quality_profile)

  args <- c(
    "--match-key", match_key,
    "--home-team", home_team,
    "--away-team", away_team,
    "--competition", competition,
    "--monitor", as.character(monitor),
    "--fps", as.character(fps),
    "--quality-profile", quality_profile,
    "--max-seconds", as.character(max_seconds),
    "--window-scale", as.character(window_scale)
  )

  if (!is.null(kickoff_utc) && nzchar(kickoff_utc)) {
    args <- c(args, "--kickoff-utc", kickoff_utc)
  }
  if (!is.null(profile_name) && nzchar(profile_name)) {
    args <- c(args, "--profile-name", profile_name)
  }
  if (!is.null(mock_video) && nzchar(mock_video)) {
    args <- c(args, "--mock-video", normalizePath(mock_video, winslash = "/", mustWork = TRUE))
  } else if (!is.null(region)) {
    if (length(region) != 4) {
      stop("region must contain left, top, width, and height.", call. = FALSE)
    }
    args <- c(args, "--region", as.character(region))
  } else if (select_region) {
    args <- c(args, "--select-region")
  }
  if (save_profile) {
    args <- c(args, "--save-profile")
  }
  if (launch_tagger) {
    args <- c(args, "--launch-tagger")
  }
  if (skip_previews) {
    args <- c(args, "--skip-previews")
  }
  if (no_preview) {
    args <- c(args, "--no-preview")
  }

  run_python_script("scripts/capture_film_study_screen.py", args)
}

extract_film_study_clips <- function(
    events_csv = file.path(getwd(), "data", "processed", "film_study", "film_study_events_enriched.csv"),
    seconds_before = 3,
    seconds_after = 4,
    event_types = NULL,
    overwrite = FALSE) {

  args <- c(
    "--events-csv", normalizePath(events_csv, winslash = "/", mustWork = TRUE),
    "--seconds-before", as.character(seconds_before),
    "--seconds-after", as.character(seconds_after)
  )

  if (!is.null(event_types) && length(event_types) > 0) {
    args <- c(args, "--event-types", event_types)
  }
  if (overwrite) {
    args <- c(args, "--overwrite")
  }

  run_python_script("scripts/extract_film_study_clips.py", args)
}

build_film_study_duckdb <- function() {
  run_python_script("scripts/build_film_study_duckdb.py")
}

build_video_quality_audit <- function() {
  run_python_script("scripts/build_video_quality_audit.py")
}

build_film_study_session_index <- function() {
  run_python_script("scripts/build_film_study_session_index.py")
}

refresh_film_study_analysis <- function() {
  build_film_study_dataset()
  build_film_study_features()
}

refresh_film_study_analysis_bundle <- function(
    extract_clips = FALSE,
    clip_event_types = NULL,
    clip_seconds_before = 3,
    clip_seconds_after = 4,
    overwrite_clips = FALSE,
    build_duckdb = TRUE) {

  refresh_film_study_analysis()

  if (extract_clips) {
    extract_film_study_clips(
      seconds_before = clip_seconds_before,
      seconds_after = clip_seconds_after,
      event_types = clip_event_types,
      overwrite = overwrite_clips
    )
  }

  if (build_duckdb) {
    build_film_study_duckdb()
  }

  build_video_quality_audit()
}

load_film_study_outputs <- function() {
  film_dir <- file.path(getwd(), "data", "processed", "film_study")
  outputs <- list(
    tags = file.path(film_dir, "film_study_tags.csv"),
    events = file.path(film_dir, "film_study_events_enriched.csv"),
    possessions = file.path(film_dir, "film_study_possessions.csv"),
    match_features = file.path(film_dir, "film_study_match_features.csv"),
    zone_summary = file.path(film_dir, "film_study_zone_summary.csv"),
    transitions = file.path(film_dir, "film_study_event_transitions.csv"),
    dictionary = file.path(film_dir, "film_study_data_dictionary.csv")
  )

  missing <- names(outputs)[!file.exists(unlist(outputs))]
  if (length(missing) > 0) {
    stop(
      "Missing film-study outputs: ",
      paste(missing, collapse = ", "),
      ". Run refresh_film_study_analysis() first.",
      call. = FALSE
    )
  }

  lapply(outputs, utils::read.csv, stringsAsFactors = FALSE)
}

ingest_latest_local_video <- function(
    source_dir,
    match_key,
    home_team,
    away_team,
    competition = "World Cup 2026",
    kickoff_utc = NULL,
    launch_tagger = FALSE,
    skip_previews = FALSE) {

  args <- c(
    "--source-dir", normalizePath(source_dir, winslash = "/", mustWork = TRUE),
    "--match-key", match_key,
    "--home-team", home_team,
    "--away-team", away_team,
    "--competition", competition
  )

  if (!is.null(kickoff_utc) && nzchar(kickoff_utc)) {
    args <- c(args, "--kickoff-utc", kickoff_utc)
  }
  if (launch_tagger) {
    args <- c(args, "--launch-tagger")
  }
  if (skip_previews) {
    args <- c(args, "--skip-previews")
  }

  run_python_script("scripts/ingest_latest_local_video.py", args)
}

watch_for_next_video <- function(
    source_dir,
    match_key,
    home_team,
    away_team,
    competition = "World Cup 2026",
    kickoff_utc = NULL,
    poll_seconds = 10,
    timeout_seconds = 0,
    allow_existing_latest = FALSE,
    launch_tagger = FALSE,
    skip_previews = FALSE) {

  args <- c(
    "--source-dir", normalizePath(source_dir, winslash = "/", mustWork = TRUE),
    "--match-key", match_key,
    "--home-team", home_team,
    "--away-team", away_team,
    "--competition", competition,
    "--poll-seconds", as.character(poll_seconds),
    "--timeout-seconds", as.character(timeout_seconds)
  )

  if (!is.null(kickoff_utc) && nzchar(kickoff_utc)) {
    args <- c(args, "--kickoff-utc", kickoff_utc)
  }
  if (allow_existing_latest) {
    args <- c(args, "--allow-existing-latest")
  }
  if (launch_tagger) {
    args <- c(args, "--launch-tagger")
  }
  if (skip_previews) {
    args <- c(args, "--skip-previews")
  }

  run_python_script("scripts/watch_for_next_video.py", args)
}
