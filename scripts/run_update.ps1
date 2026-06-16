param(
    [ValidateSet("free-refresh", "local-rebuild")]
    [string]$Profile = "free-refresh",

    [switch]$IncludeKeyedApis,
    [switch]$IncludeOddsQuota,
    [switch]$SkipNews,
    [switch]$SkipWeather,
    [switch]$SkipWikidata,
    [switch]$SkipModel,
    [switch]$SkipRender,
    [switch]$ContinueOnError
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

$Python = Join-Path $ProjectRoot ".venv\Scripts\python.exe"
if (-not (Test-Path $Python)) {
    throw "Could not find project Python at $Python"
}

$ArgsList = @("scripts\update_pipeline.py", "--profile", $Profile)

if ($IncludeKeyedApis) {
    $ArgsList += "--include-keyed-apis"
}
if ($IncludeOddsQuota) {
    $ArgsList += "--include-odds-quota"
}
if ($SkipNews) {
    $ArgsList += "--skip-news"
}
if ($SkipWeather) {
    $ArgsList += "--skip-weather"
}
if ($SkipWikidata) {
    $ArgsList += "--skip-wikidata"
}
if ($SkipModel) {
    $ArgsList += "--skip-model"
}
if ($SkipRender) {
    $ArgsList += "--skip-render"
}
if ($ContinueOnError) {
    $ArgsList += "--continue-on-error"
}

& $Python @ArgsList
exit $LASTEXITCODE
