param(
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
  "--api-football-max-fixtures", "0",
  "--api-football-max-player-pages", "0",
  "--skip-wikidata",
  "--skip-weather",
  "--skip-news"
)

if ($SkipRender) {
  $Args += "--skip-render"
}

& $Python @Args
$PipelineExitCode = $LASTEXITCODE
if ($PipelineExitCode -ne 0) {
  throw "Refresh pipeline failed with exit code $PipelineExitCode. Nothing will be published."
}

if (-not $SkipRender) {
  $LatestRunPath = Join-Path $ProjectRoot "data\processed\update_runs\latest.json"
  if (Test-Path $LatestRunPath) {
    $LatestRun = Get-Content $LatestRunPath -Raw | ConvertFrom-Json
    $RenderStep = $LatestRun.steps | Where-Object { $_.name -eq "Render R Markdown reports" } | Select-Object -First 1
    if ($RenderStep -and $RenderStep.status -ne "ok") {
      throw "Quarto render failed. Nothing will be published."
    }
  }
}

if ($Publish) {
  if ($SkipRender) {
    throw "Cannot publish when -SkipRender is set."
  }

  git add docs
  if ($LASTEXITCODE -ne 0) {
    throw "Could not stage the rendered site."
  }

  git diff --cached --quiet
  if ($LASTEXITCODE -eq 0) {
    Write-Host "No rendered site changes to publish."
    exit 0
  }
  if ($LASTEXITCODE -ne 1) {
    throw "Could not inspect the staged site changes."
  }

  $Stamp = Get-Date -Format "yyyy-MM-dd HH:mm"
  git commit -m "Post-match data refresh $Stamp"
  if ($LASTEXITCODE -ne 0) {
    throw "Could not commit the rendered site."
  }

  git push origin main
  if ($LASTEXITCODE -ne 0) {
    throw "Could not push the rendered site."
  }
}
