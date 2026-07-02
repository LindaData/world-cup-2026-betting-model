source("R/00_setup.R")

model_dir <- file.path("data", "processed", "modeling")
dir.create(model_dir, recursive = TRUE, showWarnings = FALSE)

board_path <- file.path(model_dir, "matchday_prediction_board.csv")
if (!file.exists(board_path)) {
  stop("Missing matchday_prediction_board.csv. Run R/17_matchday_prediction_board.R first.")
}

board <- readr::read_csv(board_path, show_col_types = FALSE)

safe_text <- function(x) {
  ifelse(is.na(x), "", as.character(x))
}

slug_text <- function(x) {
  x <- iconv(safe_text(x), to = "ASCII//TRANSLIT")
  x <- tolower(x)
  x <- gsub("[^a-z0-9]+", "-", x)
  gsub("(^-+|-+$)", "", x)
}

queue <- board |>
  dplyr::mutate(
    match_key = paste0("wc2026-", .data$source_match_id),
    is_future = .data$match_timing %in% c("Today", "Upcoming", "Pending score"),
    file_stub = paste0(
      .data$match_key,
      "__",
      slug_text(.data$home_team),
      "-vs-",
      slug_text(.data$away_team)
    ),
    suggested_file_name = paste0(.data$file_stub, ".mp4"),
    recording_folder = "data/private/recordings/",
    official_watch_platform = "Peacock",
    official_watch_url = "https://www.peacocktv.com/",
    queue_status = dplyr::case_when(
      .data$match_timing == "Today" ~ "Ready to record today",
      .data$match_timing == "Upcoming" ~ "Upcoming recording target",
      .data$match_timing == "Pending score" ~ "Backfill if you recorded it",
      TRUE ~ "No action"
    )
  ) |>
  dplyr::filter(.data$is_future) |>
  dplyr::transmute(
    match_key,
    date,
    match_timing,
    match_label,
    home_team,
    away_team,
    city,
    country,
    kickoff_utc_iso,
    queue_status,
    recording_folder,
    suggested_file_name,
    official_watch_platform,
    official_watch_url
  ) |>
  dplyr::arrange(.data$date, .data$match_label)

readr::write_csv(queue, file.path(model_dir, "local_recording_queue.csv"))

message("Built local recording queue: ", file.path(model_dir, "local_recording_queue.csv"))
