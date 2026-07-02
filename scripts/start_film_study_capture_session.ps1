param(
  [Parameter(Mandatory = $true)]
  [string]$MatchKey,

  [Parameter(Mandatory = $true)]
  [string]$HomeTeam,

  [Parameter(Mandatory = $true)]
  [string]$AwayTeam,

  [string]$Competition = "World Cup 2026",
  [string]$KickoffUtc = "",
  [string]$QualityProfile = "archive",
  [int]$Fps = 30,
  [string]$ProfileName = ""
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$rscript = "C:\Program Files\R\R-4.1.1\bin\Rscript.exe"
if (-not (Test-Path $rscript)) {
  throw "Rscript.exe not found at $rscript"
}

$expression = @"
source('R/38_capture_and_process_film_study_session.R')
capture_and_process_film_study_session(
  match_key = '$MatchKey',
  home_team = '$HomeTeam',
  away_team = '$AwayTeam',
  competition = '$Competition',
  kickoff_utc = '$KickoffUtc',
  select_region = $(if ($ProfileName) { "FALSE" } else { "TRUE" }),
  profile_name = '$ProfileName',
  quality_profile = '$QualityProfile',
  fps = $Fps
)
"@

& $rscript -e $expression
