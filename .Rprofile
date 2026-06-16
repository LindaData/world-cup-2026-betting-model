project_library <- file.path(getwd(), ".r-lib", paste0(R.version$major, ".", R.version$minor))
dir.create(project_library, recursive = TRUE, showWarnings = FALSE)
.libPaths(c(project_library, .libPaths()))

if (interactive()) {
  message("Project R library: ", project_library)
}

base_python <- file.path(Sys.getenv("LOCALAPPDATA"), "Programs", "Python", "Python310", "python.exe")
if (file.exists(base_python) && identical(Sys.getenv("RETICULATE_PYTHON"), "")) {
  Sys.setenv(RETICULATE_PYTHON = normalizePath(base_python, winslash = "/", mustWork = TRUE))
}
