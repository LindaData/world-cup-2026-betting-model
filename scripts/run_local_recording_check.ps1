$ErrorActionPreference = "Stop"

function Get-RscriptPath {
  $candidates = @(
    "C:\Program Files\R\R-4.1.1\bin\Rscript.exe",
    "C:\Program Files\R\R-4.1.1\bin\x64\Rscript.exe",
    "C:\Program Files\R\R-4.0.0\bin\Rscript.exe",
    "C:\Program Files\R\R-4.0.0\bin\x64\Rscript.exe"
  )

  foreach ($candidate in $candidates) {
    if (Test-Path $candidate) {
      return $candidate
    }
  }

  throw "Rscript.exe not found."
}

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$rscript = Get-RscriptPath

& $rscript "R/27_build_recording_queue.R"
& $rscript "R/26_build_local_recording_registry.R"
& $rscript "R/25_build_game_archive.R"
& $rscript "R/12_render_reports.R"

Write-Host "Local recording check complete."
