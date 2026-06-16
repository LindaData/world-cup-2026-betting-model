# Check whether RStudio can see and use the project's Python environment.
#
# Run after creating .venv:
# source("R/02_check_python_bridge.R")

source("R/00_setup.R")

venv_python <- file.path(here::here(), ".venv", "Scripts", "python.exe")
base_python <- file.path(Sys.getenv("LOCALAPPDATA"), "Programs", "Python", "Python310", "python.exe")

if (file.exists(venv_python)) {
  message("Project venv Python exists: ", venv_python)
  message("Testing venv Python through cmd.exe...")
  print(system("cmd /c .venv\\Scripts\\python.exe --version", intern = TRUE))
} else {
  message("Project Python not found yet: ", venv_python)
  message("Create it with: python -m venv .venv")
}

if (file.exists(base_python)) {
  reticulate::use_python(base_python, required = TRUE)
  message("Using base Python for reticulate: ", base_python)
} else {
  message("Base Python not found for reticulate: ", base_python)
}

print(reticulate::py_config())

