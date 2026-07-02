source("R/00_setup.R")

model_dir <- file.path("data", "processed", "modeling")
dir.create(model_dir, recursive = TRUE, showWarnings = FALSE)

recording_dir <- file.path("data", "private", "recordings")
dir.create(recording_dir, recursive = TRUE, showWarnings = FALSE)

watch_registry_path <- file.path(model_dir, "game_archive_watch_registry.csv")
board_path <- file.path(model_dir, "matchday_prediction_board.csv")

if (!file.exists(board_path)) {
  stop("Missing matchday_prediction_board.csv. Run R/17_matchday_prediction_board.R first.")
}

board <- readr::read_csv(board_path, show_col_types = FALSE) |>
  dplyr::mutate(
    match_key = paste0("wc2026-", .data$source_match_id)
  ) |>
  dplyr::select("match_key", "date", "match_label", "home_team", "away_team") |>
  dplyr::distinct()

safe_text <- function(x) {
  ifelse(is.na(x), "", as.character(x))
}

normalize_text <- function(x) {
  x <- safe_text(x)
  x <- iconv(x, to = "ASCII//TRANSLIT")
  x <- tolower(x)
  gsub("[^a-z0-9]+", "-", x)
}

recording_files <- list.files(
  recording_dir,
  pattern = "\\.(mp4|mkv|mov|avi|m4v|webm)$",
  recursive = TRUE,
  full.names = TRUE,
  ignore.case = TRUE
)

detect_match_key <- function(file_name, board) {
  base_name <- basename(file_name)
  lower_name <- tolower(base_name)
  direct <- regmatches(lower_name, regexpr("wc2026-[0-9]+", lower_name))
  if (length(direct) > 0 && nzchar(direct[[1]])) {
    return(direct[[1]])
  }

  normalized_name <- normalize_text(tools::file_path_sans_ext(base_name))
  board_match <- board |>
    dplyr::mutate(
      slug = paste(
        normalize_text(.data$date),
        normalize_text(.data$home_team),
        "vs",
        normalize_text(.data$away_team),
        sep = "-"
      )
    ) |>
    dplyr::filter(grepl(.data$slug, normalized_name, fixed = TRUE)) |>
    dplyr::slice_head(n = 1)

  if (nrow(board_match) > 0) safe_text(board_match$match_key[[1]]) else ""
}

registry <- if (length(recording_files) == 0) {
  data.frame(
    match_key = character(),
    recording_found = logical(),
    recording_file_name = character(),
    recording_relative_path = character(),
    recording_extension = character(),
    recording_size_gb = double(),
    recording_modified_utc = character(),
    stringsAsFactors = FALSE
  )
} else {
  info <- file.info(recording_files)
  rows <- lapply(seq_along(recording_files), function(i) {
    file_name <- basename(recording_files[[i]])
    data.frame(
      match_key = detect_match_key(file_name, board),
      recording_found = TRUE,
      recording_file_name = file_name,
      recording_relative_path = sub("^data/private/recordings[/\\\\]?", "", recording_files[[i]]),
      recording_extension = tolower(tools::file_ext(file_name)),
      recording_size_gb = as.numeric(info$size[[i]]) / (1024^3),
      recording_modified_utc = format(info$mtime[[i]], tz = "UTC", usetz = TRUE),
      stringsAsFactors = FALSE
    )
  })
  dplyr::bind_rows(rows) |>
    dplyr::filter(nzchar(.data$match_key)) |>
    dplyr::arrange(dplyr::desc(.data$recording_modified_utc), .data$match_key) |>
    dplyr::distinct(.data$match_key, .keep_all = TRUE)
}

registry_full <- board |>
  dplyr::left_join(registry, by = "match_key") |>
  dplyr::mutate(
    recording_found = dplyr::coalesce(.data$recording_found, FALSE),
    recording_file_name = dplyr::coalesce(.data$recording_file_name, ""),
    recording_relative_path = dplyr::coalesce(.data$recording_relative_path, ""),
    recording_extension = dplyr::coalesce(.data$recording_extension, ""),
    recording_modified_utc = dplyr::coalesce(.data$recording_modified_utc, ""),
    recording_status = dplyr::case_when(
      .data$recording_found ~ "Local film saved",
      TRUE ~ "No local film saved yet"
    )
  ) |>
  dplyr::arrange(.data$date, .data$match_label)

readr::write_csv(registry_full, file.path(model_dir, "local_recording_registry.csv"))

message("Built local recording registry: ", file.path(model_dir, "local_recording_registry.csv"))
message("Recording folder: ", normalizePath(recording_dir, winslash = "/", mustWork = TRUE))
