$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

& "C:\Program Files\R\R-4.1.1\bin\Rscript.exe" -e "shiny::runApp('apps/shiny_film_study', host='127.0.0.1', port=3850, launch.browser=FALSE)"
