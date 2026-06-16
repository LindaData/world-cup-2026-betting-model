# Render presentation reports.
#
# Run from RStudio:
# source("R/12_render_reports.R")

source("R/00_setup.R")

rstudio_pandoc <- "C:/Program Files/RStudio/bin/pandoc"
if (dir.exists(rstudio_pandoc)) {
  Sys.setenv(RSTUDIO_PANDOC = rstudio_pandoc)
}

if (!requireNamespace("rmarkdown", quietly = TRUE)) {
  install.packages("rmarkdown", repos = "https://cloud.r-project.org")
}

reports <- c(
  "reports/00_project_overview.Rmd",
  "reports/01_goals_linear_regression.Rmd",
  "reports/02_ordinal_result_model.Rmd"
)

for (report in reports) {
  rmarkdown::render(report, quiet = FALSE)
  message("Rendered ", sub("\\.Rmd$", ".html", report))
}
