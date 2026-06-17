library(shiny)
library(DT)
library(ggplot2)
library(readr)
library(dplyr)

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
  if (file.exists(path)) {
    readr::read_csv(path, show_col_types = FALSE)
  } else {
    data.frame()
  }
}

root <- find_project_root()
model_dir <- file.path(root, "data", "processed", "modeling")
metadata_dir <- file.path(root, "data", "processed", "metadata")

goals_sample <- read_csv_if_exists(file.path(model_dir, "goals_linear_model_sample_1000.csv"))
goals_metrics <- read_csv_if_exists(file.path(model_dir, "goals_linear_model_metrics.csv"))
result_predictions <- read_csv_if_exists(file.path(model_dir, "result_ordinal_model_test_predictions.csv"))
result_metrics <- read_csv_if_exists(file.path(model_dir, "result_ordinal_model_metrics.csv"))
table_inventory <- read_csv_if_exists(file.path(metadata_dir, "table_inventory.csv"))

team_choices <- if (nrow(goals_sample) > 0 && "team" %in% names(goals_sample)) {
  c("All", sort(unique(goals_sample$team)))
} else {
  "All"
}

ui <- navbarPage(
  title = "2026 World Cup Model",
  tabPanel(
    "About",
    sidebarLayout(
      sidebarPanel(
        h3("Project"),
        p("RStudio-first workflow for World Cup data, modeling, and publication."),
        tags$ul(
          tags$li(strong("About:"), " project overview and data source notes."),
          tags$li(strong("Data Exploration:"), " plots and row-level samples."),
          tags$li(strong("Modeling:"), " baseline model metrics and predictions."),
          tags$li(strong("Data:"), " local table inventory and preview.")
        )
      ),
      mainPanel(
        h1("2026 World Cup Betting Model"),
        p("This local Shiny app mirrors the public Quarto report but adds interactive filters."),
        p("It reads local processed files only. No API keys or private files are published.")
      )
    )
  ),
  tabPanel(
    "Data Exploration",
    sidebarLayout(
      sidebarPanel(
        selectInput("team", "Team", choices = team_choices),
        radioButtons(
          "plot_type",
          "Plot",
          choices = c("Goals histogram", "Elo vs goals"),
          selected = "Goals histogram"
        )
      ),
      mainPanel(
        plotOutput("eda_plot", height = "420px"),
        h3("Sample Rows"),
        DTOutput("goals_table")
      )
    )
  ),
  tabPanel(
    "Modeling",
    sidebarLayout(
      sidebarPanel(
        radioButtons(
          "model_pick",
          "Model",
          choices = c("Goals linear regression", "Ordinal result logistic"),
          selected = "Goals linear regression"
        )
      ),
      mainPanel(
        h3("Model Metrics"),
        DTOutput("metrics_table"),
        h3("Prediction Examples"),
        DTOutput("prediction_table")
      )
    )
  ),
  tabPanel(
    "Data",
    sidebarLayout(
      sidebarPanel(
        p("Metadata is safe to inspect and publish. Raw/processed datasets stay local.")
      ),
      mainPanel(
        h3("Local Table Inventory"),
        DTOutput("inventory_table")
      )
    )
  )
)

server <- function(input, output, session) {
  filtered_goals <- reactive({
    if (nrow(goals_sample) == 0 || input$team == "All") {
      return(goals_sample)
    }
    goals_sample %>% filter(team == input$team)
  })

  output$eda_plot <- renderPlot({
    dat <- filtered_goals()
    validate(need(nrow(dat) > 0, "Run the local refresh first to create modeling samples."))

    if (input$plot_type == "Goals histogram") {
      ggplot(dat, aes(x = y_goals_for)) +
        geom_histogram(binwidth = 1, boundary = -0.5, fill = "#157878", color = "white") +
        labs(title = "Goals scored by team-match row", x = "Goals", y = "Rows") +
        theme_minimal()
    } else {
      ggplot(dat, aes(x = pre_elo, y = y_goals_for)) +
        geom_point(alpha = 0.65, color = "#157878") +
        geom_smooth(method = "lm", se = FALSE, color = "#f2a65a") +
        labs(title = "Pre-match Elo vs goals", x = "Pre-match Elo", y = "Goals") +
        theme_minimal()
    }
  })

  output$goals_table <- renderDT({
    datatable(filtered_goals(), options = list(pageLength = 10, scrollX = TRUE), rownames = FALSE)
  })

  output$metrics_table <- renderDT({
    if (input$model_pick == "Goals linear regression") {
      dat <- goals_metrics
    } else {
      dat <- result_metrics
    }
    validate(need(nrow(dat) > 0, "Run the local refresh first to create model metrics."))
    datatable(dat, options = list(pageLength = 5, scrollX = TRUE), rownames = FALSE)
  })

  output$prediction_table <- renderDT({
    dat <- result_predictions
    validate(need(nrow(dat) > 0, "Run the ordinal result model first to create predictions."))
    cols <- intersect(
      c("date", "team", "opponent", "y_result_ordered", "predicted_result", "pred_prob_loss", "pred_prob_draw", "pred_prob_win"),
      names(dat)
    )
    datatable(dat[, cols, drop = FALSE], options = list(pageLength = 10, scrollX = TRUE), rownames = FALSE)
  })

  output$inventory_table <- renderDT({
    validate(need(nrow(table_inventory) > 0, "Run R/07_export_metadata.R first to create metadata."))
    datatable(table_inventory, options = list(pageLength = 15, scrollX = TRUE), rownames = FALSE)
  })
}

shinyApp(ui = ui, server = server)
