library(shiny)
library(DT)
library(readr)
library(dplyr)
library(tools)
library(jsonlite)

find_project_root <- function(start = getwd()) {
  current <- normalizePath(start, winslash = "/", mustWork = TRUE)
  repeat {
    if (file.exists(file.path(current, "_quarto.yml"))) {
      return(current)
    }
    parent <- dirname(current)
    if (identical(parent, current)) {
      stop("Could not find project root. Open the app from inside the project folder.")
    }
    current <- parent
  }
}

read_csv_if_exists <- function(path) {
  if (!file.exists(path)) {
    return(data.frame())
  }
  readr::read_csv(path, show_col_types = FALSE)
}

root <- find_project_root()
source(file.path(root, "R", "28_film_study_workflow.R"), local = TRUE)
source(file.path(root, "R", "29_render_film_study_review.R"), local = TRUE)
source(file.path(root, "R", "31_fit_film_study_models.R"), local = TRUE)
source(file.path(root, "R", "32_render_film_study_modeling_report.R"), local = TRUE)
source(file.path(root, "R", "33_render_film_study_quality_report.R"), local = TRUE)
source(file.path(root, "R", "34_process_film_study_session.R"), local = TRUE)
source(file.path(root, "R", "35_export_film_study_session.R"), local = TRUE)
source(file.path(root, "R", "36_fit_film_study_state_engine.R"), local = TRUE)
source(file.path(root, "R", "37_render_film_study_state_engine_report.R"), local = TRUE)
source(file.path(root, "R", "38_capture_and_process_film_study_session.R"), local = TRUE)
source(file.path(root, "R", "39_validate_film_study_setup.R"), local = TRUE)

film_processed_dir <- file.path(root, "data", "processed", "film_study")
video_library_dir <- file.path(root, "data", "private", "video_library")
clips_dir <- file.path(root, "data", "private", "clips")
reports_dir <- file.path(root, "data", "private", "reports")

app_title <- "Film Study Workbench"

ui <- fluidPage(
  tags$head(
    tags$style(HTML("
      body { background: #f6f8fb; }
      .film-card {
        background: #ffffff;
        border: 1px solid #d9e2ec;
        border-radius: 8px;
        padding: 16px;
        margin-bottom: 16px;
      }
      .film-metric {
        font-size: 28px;
        font-weight: 600;
        color: #102a43;
      }
      .film-label {
        color: #486581;
        font-size: 12px;
        text-transform: uppercase;
        letter-spacing: 0.04em;
      }
      .status-box {
        white-space: pre-wrap;
        background: #102a43;
        color: #f0f4f8;
        border-radius: 8px;
        padding: 12px;
        min-height: 120px;
      }
    "))
  ),
  titlePanel(app_title),
  fluidRow(
    column(
      width = 4,
      div(
        class = "film-card",
        h4("Video Intake"),
        textInput("source_dir", "Video folder", value = "C:/Users/14154/AppData/Local/Temp"),
        textInput("match_key", "Match key", value = "wc2026-demo-001"),
        textInput("home_team", "Home team", value = "Home"),
        textInput("away_team", "Away team", value = "Away"),
        textInput("competition", "Competition", value = "World Cup 2026"),
        textInput("kickoff_utc", "Kickoff UTC (optional)", value = ""),
        checkboxInput("skip_previews", "Skip preview stills", value = FALSE),
        actionButton("register_latest", "Register newest local video", class = "btn-primary"),
        tags$hr(),
        h5("Live Capture"),
        selectInput(
          "capture_quality",
          "Capture quality",
          choices = c("Archive quality (MJPG AVI)" = "archive", "Compact MP4" = "compact"),
          selected = "archive"
        ),
        numericInput("capture_fps", "Capture FPS", value = 30, min = 5, max = 60, step = 1),
        checkboxInput("capture_preview", "Show live preview window", value = TRUE),
        checkboxInput("use_saved_profile", "Use saved capture profile", value = FALSE),
        selectInput("capture_profile_choice", "Saved profile", choices = stats::setNames("", ""), selected = ""),
        textInput("capture_profile_name", "New or selected profile name", value = ""),
        checkboxInput("save_profile_flag", "Save selected region as profile", value = FALSE),
        actionButton("refresh_profiles", "Refresh profiles", class = "btn-default"),
        actionButton("list_monitors", "List monitors", class = "btn-default"),
        actionButton("capture_screen", "Capture selected screen region", class = "btn-warning"),
        actionButton("capture_process_screen", "Capture, tag, and process", class = "btn-warning"),
        tags$hr(),
        actionButton("watch_latest", "Use current latest file", class = "btn-default"),
        p("The watcher path is reduced here to immediate use of the current latest local file so the app stays responsive.")
      ),
      div(
        class = "film-card",
        h4("Analysis"),
        checkboxGroupInput(
          "clip_event_types",
          "Extract clips for",
          choices = c("shot", "goal", "pass", "attack_entry", "turnover", "save"),
          selected = c("shot", "goal")
        ),
        numericInput("clip_before", "Seconds before event", value = 3, min = 0, step = 0.5),
        numericInput("clip_after", "Seconds after event", value = 4, min = 0, step = 0.5),
        checkboxInput("overwrite_clips", "Overwrite existing clips", value = TRUE),
        checkboxInput("build_duckdb_flag", "Rebuild local DuckDB", value = TRUE),
        actionButton("run_bundle", "Run analysis bundle", class = "btn-success"),
        actionButton("run_full_pipeline", "Run full local pipeline", class = "btn-success"),
        tags$hr(),
        actionButton("render_review", "Render review HTML", class = "btn-default"),
        actionButton("render_quality_report", "Render quality HTML", class = "btn-default"),
        actionButton("fit_models", "Fit local models", class = "btn-default"),
        actionButton("render_model_report", "Render modeling HTML", class = "btn-default"),
        actionButton("fit_state_engine", "Fit state engine", class = "btn-default"),
        actionButton("render_state_engine_report", "Render state engine HTML", class = "btn-default"),
        actionButton("export_session", "Export match bundle", class = "btn-default")
      ),
      div(
        class = "film-card",
        h4("Setup"),
        actionButton("validate_setup", "Validate local setup", class = "btn-default"),
        actionButton("rebuild_session_index", "Rebuild session index", class = "btn-default"),
        tags$hr(),
        verbatimTextOutput("setup_summary_text")
      ),
      div(
        class = "film-card",
        h4("Status"),
        verbatimTextOutput("run_status", placeholder = TRUE)
      )
    ),
    column(
      width = 8,
      fluidRow(
        column(width = 4, div(class = "film-card", div(class = "film-label", "Tagged events"), div(class = "film-metric", textOutput("metric_events")))),
        column(width = 4, div(class = "film-card", div(class = "film-label", "Possessions"), div(class = "film-metric", textOutput("metric_possessions")))),
        column(width = 4, div(class = "film-card", div(class = "film-label", "Extracted clips"), div(class = "film-metric", textOutput("metric_clips")))),
        column(width = 4, div(class = "film-card", div(class = "film-label", "Analysis-ready videos"), div(class = "film-metric", textOutput("metric_ready_videos"))))
      ),
      tabsetPanel(
        tabPanel("Video Catalog", DTOutput("catalog_table")),
        tabPanel("Quality Audit", DTOutput("quality_table")),
        tabPanel("Match Features", DTOutput("match_features_table")),
        tabPanel("Events", DTOutput("events_table")),
        tabPanel("Grid Moves", DTOutput("grid_transitions_table")),
        tabPanel("Clips", DTOutput("clips_table")),
        tabPanel("Capture Profiles", DTOutput("profiles_table")),
        tabPanel("Sessions", DTOutput("sessions_table")),
        tabPanel("Setup Validation", verbatimTextOutput("setup_validation_path")),
        tabPanel("Review Report", verbatimTextOutput("report_path")),
        tabPanel("Quality Report", verbatimTextOutput("quality_report_path")),
        tabPanel("Model Summary", verbatimTextOutput("model_summary_text")),
        tabPanel("Modeling Report", verbatimTextOutput("model_report_path")),
        tabPanel("State Engine", DTOutput("state_engine_table")),
        tabPanel("State Engine Report", verbatimTextOutput("state_engine_report_path")),
        tabPanel("Session Index Report", verbatimTextOutput("session_index_report_path")),
        tabPanel("DuckDB", verbatimTextOutput("duckdb_path"))
      )
    )
  )
)

server <- function(input, output, session) {
  status_text <- reactiveVal("Ready.")
  setup_summary_text <- reactiveVal("Setup has not been validated yet.")
  refresh_tick <- reactiveVal(0)

  current_profile_name <- reactive({
    entered <- trimws(input$capture_profile_name)
    if (nzchar(entered)) {
      return(entered)
    }
    chosen <- trimws(input$capture_profile_choice)
    if (nzchar(chosen)) {
      return(chosen)
    }
    NULL
  })

  capture_profile_settings <- function() {
    profile_name <- current_profile_name()
    use_saved <- isTRUE(input$use_saved_profile)
    save_profile <- isTRUE(input$save_profile_flag)

    if (use_saved && is.null(profile_name)) {
      stop("Choose or enter a capture profile name before using a saved profile.", call. = FALSE)
    }
    if (save_profile && is.null(profile_name)) {
      stop("Enter a capture profile name before saving a profile.", call. = FALSE)
    }

    list(
      profile_name = profile_name,
      select_region = !use_saved,
      save_profile = save_profile
    )
  }

  observeEvent(list(refresh_tick(), input$refresh_profiles), {
    profiles <- list_capture_profiles()
    choices <- stats::setNames("", "")
    if (nrow(profiles) > 0) {
      choices <- c(choices, stats::setNames(profiles$profile_name, profiles$profile_name))
    }
    selected <- if (!is.null(input$capture_profile_choice) && input$capture_profile_choice %in% names(choices)) {
      input$capture_profile_choice
    } else {
      ""
    }
    updateSelectInput(session, "capture_profile_choice", choices = choices, selected = selected)
  }, ignoreNULL = FALSE)

  refresh_data <- reactive({
    refresh_tick()
    list(
      catalog = read_csv_if_exists(file.path(video_library_dir, "video_catalog.csv")),
      quality = read_csv_if_exists(file.path(film_processed_dir, "video_quality_audit.csv")),
      match_features = read_csv_if_exists(file.path(film_processed_dir, "film_study_match_features.csv")),
      events = read_csv_if_exists(file.path(film_processed_dir, "film_study_events_enriched.csv")),
      clips = read_csv_if_exists(file.path(clips_dir, "film_study_clips.csv")),
      grid_transitions = read_csv_if_exists(file.path(film_processed_dir, "film_study_grid_transitions.csv")),
      state_engine = read_csv_if_exists(file.path(film_processed_dir, "film_study_state_engine_summary.csv")),
      sessions = read_csv_if_exists(file.path(film_processed_dir, "film_study_session_index.csv"))
    )
  })

  run_safely <- function(expr) {
    tryCatch(
      {
        expr
        refresh_tick(refresh_tick() + 1)
        status_text(paste0(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\nCompleted successfully."))
      },
      error = function(err) {
        status_text(
          paste0(
            format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
            "\n",
            conditionMessage(err)
          )
        )
      }
    )
  }

  observeEvent(input$register_latest, {
    run_safely(
      ingest_latest_local_video(
        source_dir = input$source_dir,
        match_key = input$match_key,
        home_team = input$home_team,
        away_team = input$away_team,
        competition = input$competition,
        kickoff_utc = input$kickoff_utc,
        skip_previews = input$skip_previews
      )
    )
  })

  observeEvent(input$watch_latest, {
    run_safely(
      watch_for_next_video(
        source_dir = input$source_dir,
        match_key = input$match_key,
        home_team = input$home_team,
        away_team = input$away_team,
        competition = input$competition,
        kickoff_utc = input$kickoff_utc,
        allow_existing_latest = TRUE,
        skip_previews = input$skip_previews
      )
    )
  })

  observeEvent(input$capture_screen, {
    profile_settings <- capture_profile_settings()
    run_safely(
      capture_film_study_screen(
        match_key = input$match_key,
        home_team = input$home_team,
        away_team = input$away_team,
        competition = input$competition,
        kickoff_utc = input$kickoff_utc,
        profile_name = profile_settings$profile_name,
        save_profile = profile_settings$save_profile,
        fps = input$capture_fps,
        quality_profile = input$capture_quality,
        select_region = profile_settings$select_region,
        skip_previews = input$skip_previews,
        no_preview = !isTRUE(input$capture_preview)
      )
    )
  })

  observeEvent(input$list_monitors, {
    tryCatch(
      {
        monitors <- list_capture_monitors()
        refresh_tick(refresh_tick() + 1)
        status_text(
          paste0(
            format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
            "\n",
            paste(capture.output(print(monitors)), collapse = "\n")
          )
        )
      },
      error = function(err) {
        status_text(
          paste0(
            format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
            "\n",
            conditionMessage(err)
          )
        )
      }
    )
  })

  observeEvent(input$capture_process_screen, {
    profile_settings <- capture_profile_settings()
    run_safely(
      capture_and_process_film_study_session(
        match_key = input$match_key,
        home_team = input$home_team,
        away_team = input$away_team,
        competition = input$competition,
        kickoff_utc = input$kickoff_utc,
        profile_name = profile_settings$profile_name,
        save_profile = profile_settings$save_profile,
        fps = input$capture_fps,
        quality_profile = input$capture_quality,
        select_region = profile_settings$select_region,
        no_preview = !isTRUE(input$capture_preview),
        skip_previews = input$skip_previews,
        extract_clips = TRUE,
        clip_event_types = input$clip_event_types,
        clip_seconds_before = input$clip_before,
        clip_seconds_after = input$clip_after,
        overwrite_clips = input$overwrite_clips,
        build_duckdb = input$build_duckdb_flag,
        fit_models = TRUE,
        fit_state_engine = TRUE,
        create_preset_template = TRUE,
        export_session_bundle = TRUE,
        render_review_report = TRUE,
        render_quality_report = TRUE,
        render_modeling_report = TRUE,
        render_state_engine_report = TRUE
      )
    )
  })

  observeEvent(input$run_bundle, {
    run_safely(
      refresh_film_study_analysis_bundle(
        extract_clips = TRUE,
        clip_event_types = input$clip_event_types,
        clip_seconds_before = input$clip_before,
        clip_seconds_after = input$clip_after,
        overwrite_clips = input$overwrite_clips,
        build_duckdb = input$build_duckdb_flag
      )
    )
  })

  observeEvent(input$run_full_pipeline, {
    run_safely(
      process_film_study_session(
        source_dir = input$source_dir,
        match_key = input$match_key,
        home_team = input$home_team,
        away_team = input$away_team,
        competition = input$competition,
        kickoff_utc = input$kickoff_utc,
        skip_previews = input$skip_previews,
        extract_clips = TRUE,
        clip_event_types = input$clip_event_types,
        clip_seconds_before = input$clip_before,
        clip_seconds_after = input$clip_after,
        overwrite_clips = input$overwrite_clips,
        skip_duckdb = !isTRUE(input$build_duckdb_flag),
        fit_models = TRUE,
        render_review_report = TRUE,
        render_quality_report = TRUE,
        render_modeling_report = TRUE
      )
    )
  })

  observeEvent(input$render_review, {
    run_safely(render_film_study_review())
  })

  observeEvent(input$render_quality_report, {
    run_safely(render_film_study_quality_report())
  })

  observeEvent(input$fit_models, {
    run_safely(fit_film_study_models())
  })

  observeEvent(input$render_model_report, {
    run_safely(render_film_study_modeling_report())
  })

  observeEvent(input$fit_state_engine, {
    run_safely(fit_film_study_state_engine())
  })

  observeEvent(input$render_state_engine_report, {
    run_safely(render_film_study_state_engine_report())
  })

  observeEvent(input$export_session, {
    run_safely({
      export_film_study_session(input$match_key)
      build_film_study_session_index()
    })
  })

  observeEvent(input$validate_setup, {
    tryCatch(
      {
        validation <- validate_local_film_study_setup()
        refresh_tick(refresh_tick() + 1)
        setup_summary_text(paste(capture.output(print(validation)), collapse = "\n"))
        status_text(paste0(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\nSetup validation completed."))
      },
      error = function(err) {
        status_text(
          paste0(
            format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
            "\n",
            conditionMessage(err)
          )
        )
      }
    )
  })

  observeEvent(input$rebuild_session_index, {
    run_safely(build_film_study_session_index())
  })

  output$run_status <- renderText(status_text())
  output$setup_summary_text <- renderText(setup_summary_text())

  output$metric_events <- renderText({
    dat <- refresh_data()$events
    if (nrow(dat) == 0) "0" else format(nrow(dat), big.mark = ",")
  })

  output$metric_possessions <- renderText({
    dat <- read_csv_if_exists(file.path(film_processed_dir, "film_study_possessions.csv"))
    if (nrow(dat) == 0) "0" else format(nrow(dat), big.mark = ",")
  })

  output$metric_clips <- renderText({
    dat <- refresh_data()$clips
    if (nrow(dat) == 0) "0" else format(sum(dat$clip_status == "ok", na.rm = TRUE), big.mark = ",")
  })

  output$metric_ready_videos <- renderText({
    dat <- refresh_data()$quality
    if (nrow(dat) == 0) {
      "0"
    } else {
      format(sum(dat$analysis_ready_resolution & dat$analysis_ready_fps, na.rm = TRUE), big.mark = ",")
    }
  })

  output$catalog_table <- renderDT({
    datatable(refresh_data()$catalog, options = list(pageLength = 10, scrollX = TRUE), rownames = FALSE)
  })

  output$quality_table <- renderDT({
    datatable(refresh_data()$quality, options = list(pageLength = 10, scrollX = TRUE), rownames = FALSE)
  })

  output$match_features_table <- renderDT({
    datatable(refresh_data()$match_features, options = list(pageLength = 10, scrollX = TRUE), rownames = FALSE)
  })

  output$events_table <- renderDT({
    dat <- refresh_data()$events
    cols <- intersect(
      c("match_key", "event_index", "event_type", "team_inferred", "player", "time_seconds", "pitch_cell_12x8", "pitch_board_cell", "movement_direction", "transition_vector_12x8", "transition_shape", "x_zone", "y_lane", "possession_id", "next_event_type", "next_pitch_cell_12x8", "next_pitch_board_cell"),
      names(dat)
    )
    datatable(dat[, cols, drop = FALSE], options = list(pageLength = 12, scrollX = TRUE), rownames = FALSE)
  })

  output$grid_transitions_table <- renderDT({
    dat <- refresh_data()$grid_transitions
    cols <- intersect(
      c("match_key", "team_inferred", "pitch_board_cell", "next_pitch_board_cell", "movement_direction", "transition_vector_12x8", "transition_shape", "transition_count", "transition_rate_from_cell", "avg_manhattan_cell_distance"),
      names(dat)
    )
    datatable(dat[, cols, drop = FALSE], options = list(pageLength = 12, scrollX = TRUE), rownames = FALSE)
  })

  output$clips_table <- renderDT({
    dat <- refresh_data()$clips
    datatable(dat, options = list(pageLength = 10, scrollX = TRUE), rownames = FALSE)
  })

  output$profiles_table <- renderDT({
    dat <- list_capture_profiles()
    datatable(dat, options = list(pageLength = 10, scrollX = TRUE), rownames = FALSE)
  })

  output$sessions_table <- renderDT({
    dat <- refresh_data()$sessions
    datatable(dat, options = list(pageLength = 10, scrollX = TRUE), rownames = FALSE)
  })

  output$state_engine_table <- renderDT({
    dat <- refresh_data()$state_engine
    cols <- intersect(
      c("state_id", "event_group", "pitch_cell", "board_cell", "movement_direction", "transition_shape", "visits", "next_shot_prob", "next_goal_prob", "next_turnover_prob", "possession_shot_prob", "possession_goal_prob", "avg_forward_cell_progress", "final_third_entry_rate", "most_likely_next_board_cell", "engine_advantage"),
      names(dat)
    )
    datatable(dat[, cols, drop = FALSE], options = list(pageLength = 10, scrollX = TRUE), rownames = FALSE)
  })

  output$report_path <- renderText({
    report_path <- file.path(reports_dir, "film_study_review.html")
    if (file.exists(report_path)) normalizePath(report_path, winslash = "/") else "Report not rendered yet."
  })

  output$model_report_path <- renderText({
    report_path <- file.path(reports_dir, "film_study_modeling.html")
    if (file.exists(report_path)) normalizePath(report_path, winslash = "/") else "Modeling report not rendered yet."
  })

  output$quality_report_path <- renderText({
    report_path <- file.path(reports_dir, "film_study_quality.html")
    if (file.exists(report_path)) normalizePath(report_path, winslash = "/") else "Quality report not rendered yet."
  })

  output$state_engine_report_path <- renderText({
    report_path <- file.path(reports_dir, "film_study_state_engine.html")
    if (file.exists(report_path)) normalizePath(report_path, winslash = "/") else "State engine report not rendered yet."
  })

  output$session_index_report_path <- renderText({
    report_path <- file.path(reports_dir, "film_study_session_index.html")
    if (file.exists(report_path)) normalizePath(report_path, winslash = "/") else "Session index report not rendered yet."
  })

  output$setup_validation_path <- renderText({
    report_path <- file.path(film_processed_dir, "film_study_setup_validation.json")
    if (file.exists(report_path)) normalizePath(report_path, winslash = "/") else "Setup validation has not been run yet."
  })

  output$model_summary_text <- renderText({
    summary_path <- file.path(film_processed_dir, "film_study_model_summary.json")
    if (!file.exists(summary_path)) {
      return("Model summary not created yet.")
    }
    paste(readLines(summary_path, warn = FALSE), collapse = "\n")
  })

  output$duckdb_path <- renderText({
    db_path <- file.path(root, "data", "processed", "film_study.duckdb")
    if (file.exists(db_path)) normalizePath(db_path, winslash = "/") else "DuckDB file not built yet."
  })
}

shinyApp(ui = ui, server = server)
