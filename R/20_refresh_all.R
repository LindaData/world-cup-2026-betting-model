# Local refresh wrapper for RStudio.
#
# This script defines refresh_world_cup_data(). It does not run automatically when sourced,
# so you can choose whether to rebuild locally or pull live free sources.
#
# In RStudio:
# source("R/20_refresh_all.R")
# refresh_world_cup_data(profile = "local-rebuild")
# refresh_world_cup_data(profile = "free-refresh")

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

refresh_world_cup_data <- function(
    profile = c("free-refresh", "local-rebuild"),
    include_keyed_apis = FALSE,
    include_odds_quota = FALSE,
    skip_news = FALSE,
    skip_weather = FALSE,
    skip_wikidata = FALSE,
    skip_model = FALSE,
    skip_render = FALSE,
    continue_on_error = FALSE,
    include_api_football_advanced = FALSE,
    api_football_max_fixtures = 0,
    api_football_max_player_pages = 1,
    max_weather_fixtures = NULL,
    max_news_records = NULL,
    news_timespan = NULL) {

  profile <- match.arg(profile)
  python <- project_python()

  args <- c("scripts/update_pipeline.py", "--profile", profile)

  if (include_keyed_apis) {
    args <- c(args, "--include-keyed-apis")
  }
  if (include_odds_quota) {
    args <- c(args, "--include-odds-quota")
  }
  if (include_api_football_advanced) {
    args <- c(args, "--api-football-advanced")
  }
  if (!is.null(api_football_max_fixtures)) {
    args <- c(args, "--api-football-max-fixtures", as.character(api_football_max_fixtures))
  }
  if (!is.null(api_football_max_player_pages)) {
    args <- c(args, "--api-football-max-player-pages", as.character(api_football_max_player_pages))
  }
  if (skip_news) {
    args <- c(args, "--skip-news")
  }
  if (skip_weather) {
    args <- c(args, "--skip-weather")
  }
  if (skip_wikidata) {
    args <- c(args, "--skip-wikidata")
  }
  if (skip_model) {
    args <- c(args, "--skip-model")
  }
  if (skip_render) {
    args <- c(args, "--skip-render")
  }
  if (continue_on_error) {
    args <- c(args, "--continue-on-error")
  }
  if (!is.null(max_weather_fixtures)) {
    args <- c(args, "--max-weather-fixtures", as.character(max_weather_fixtures))
  }
  if (!is.null(max_news_records)) {
    args <- c(args, "--max-news-records", as.character(max_news_records))
  }
  if (!is.null(news_timespan)) {
    args <- c(args, "--news-timespan", news_timespan)
  }

  message("Running local refresh with: ", python, " ", paste(args, collapse = " "))
  exit_code <- system2(python, args = args)

  if (!identical(exit_code, 0L)) {
    stop("Refresh failed with exit code ", exit_code, ". See data/processed/update_runs/latest.json.")
  }

  message("Refresh complete. Open docs/current_data_status.md for the latest table counts and run log.")
  invisible(exit_code)
}
