$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$rscript = "C:\Program Files\R\R-4.1.1\bin\Rscript.exe"
if (-not (Test-Path $rscript)) {
  throw "Rscript.exe not found at $rscript"
}

Write-Host "Validating local film-study setup..."
& $rscript -e "source('R/39_validate_film_study_setup.R'); print(validate_local_film_study_setup())"

Write-Host "Launching Film Study Workbench on http://127.0.0.1:3850 ..."
& $rscript -e "shiny::runApp('apps/shiny_film_study', host='127.0.0.1', port=3850, launch.browser=TRUE)"
