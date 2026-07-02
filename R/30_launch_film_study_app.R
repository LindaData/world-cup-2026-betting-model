# Launch the local film-study Shiny app.
#
# In RStudio:
# source("R/30_launch_film_study_app.R")
# launch_film_study_app()

launch_film_study_app <- function(
    app_dir = "apps/shiny_film_study",
    launch_browser = TRUE,
    port = NULL) {

  if (!requireNamespace("shiny", quietly = TRUE)) {
    stop("Package 'shiny' is required. Install it with install.packages('shiny').", call. = FALSE)
  }

  shiny::runApp(
    appDir = app_dir,
    launch.browser = launch_browser,
    port = port
  )
}
