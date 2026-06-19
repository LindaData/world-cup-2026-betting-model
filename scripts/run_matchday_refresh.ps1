param(
  [int]$FixtureDetails = 4,
  [int]$PlayerPages = 1,
  [switch]$SkipRender,
  [switch]$Publish
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $ProjectRoot

$Python = Join-Path $ProjectRoot ".venv\Scripts\python.exe"
if (-not (Test-Path $Python)) {
  throw "Python virtual environment not found at $Python"
}

$Args = @(
  "scripts\update_pipeline.py",
  "--profile", "free-refresh",
  "--include-keyed-apis",
  "--api-football-advanced",
  "--api-football-max-fixtures", "$FixtureDetails",
  "--api-football-max-player-pages", "$PlayerPages",
  "--max-weather-fixtures", "72",
  "--max-news-records", "75",
  "--news-timespan", "24h"
)

if ($SkipRender) {
  $Args += "--skip-render"
}

& $Python @Args

if ($Publish) {
  if ($SkipRender) {
    throw "Cannot publish when -SkipRender is set."
  }

  git add docs
  git diff --cached --quiet
  if ($LASTEXITCODE -eq 0) {
    Write-Host "No rendered site changes to publish."
    exit 0
  }

  $Stamp = Get-Date -Format "yyyy-MM-dd HH:mm"
  git commit -m "Refresh matchday predictions $Stamp"
  git push origin main
  git subtree push --prefix docs origin gh-pages
}
