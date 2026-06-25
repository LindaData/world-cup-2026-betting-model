param(
  [switch]$Publish,
  [switch]$Force
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$SchedulePath = Join-Path $ProjectRoot "data\processed\modeling\matchday_postmatch_refresh_schedule.csv"
$RefreshScript = Join-Path $ProjectRoot "scripts\run_postmatch_refresh.ps1"

if (-not (Test-Path $SchedulePath)) {
  throw "Post-match refresh schedule not found at $SchedulePath. Run R\17_matchday_prediction_board.R first."
}

if (-not (Test-Path $RefreshScript)) {
  throw "Post-match refresh script not found at $RefreshScript."
}

$Rows = Import-Csv $SchedulePath
$Now = Get-Date
$EasternTimeZone = [System.TimeZoneInfo]::FindSystemTimeZoneById("Eastern Standard Time")
$LocalTimeZone = [System.TimeZoneInfo]::Local
$DateFormat = "yyyy-MM-dd HH:mm:ss"

$FutureRows = foreach ($Row in $Rows) {
  if (-not $Row.postmatch_refresh_at_eastern) {
    continue
  }

  $EasternUnspecified = [datetime]::ParseExact(
    $Row.postmatch_refresh_at_eastern,
    $DateFormat,
    [System.Globalization.CultureInfo]::InvariantCulture
  )
  $RunAtLocal = [System.TimeZoneInfo]::ConvertTime(
    $EasternUnspecified,
    $EasternTimeZone,
    $LocalTimeZone
  )

  if ($RunAtLocal -gt $Now) {
    [pscustomobject]@{
      RunAtLocal = $RunAtLocal
      RunAtEasternText = $Row.postmatch_refresh_at_eastern
      MatchLabel = $Row.match_label
      SourceMatchId = $Row.source_match_id
    }
  }
}

$Grouped = $FutureRows | Group-Object RunAtEasternText
$Created = 0

foreach ($Group in $Grouped) {
  $RunAtLocal = ($Group.Group | Select-Object -First 1).RunAtLocal
  $TaskStamp = $RunAtLocal.ToString("yyyyMMdd_HHmm")
  $TaskName = "LindaData_WorldCup_PostMatchRefresh_$TaskStamp"
  $Description = "Refresh World Cup model after: " + (($Group.Group | Select-Object -ExpandProperty MatchLabel) -join "; ")

  $ScriptArgs = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", "`"$RefreshScript`""
  )

  if ($Publish) {
    $ScriptArgs += "-Publish"
  }

  $Action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument ($ScriptArgs -join " ") `
    -WorkingDirectory $ProjectRoot

  $Trigger = New-ScheduledTaskTrigger -Once -At $RunAtLocal
  $Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Hours 2)

  if ($Force) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
  }

  $ExistingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

  if ($ExistingTask) {
    Set-ScheduledTask `
      -TaskName $TaskName `
      -Action $Action `
      -Trigger $Trigger `
      -Settings $Settings | Out-Null
  } else {
    Register-ScheduledTask `
      -TaskName $TaskName `
      -Action $Action `
      -Trigger $Trigger `
      -Settings $Settings `
      -Description $Description | Out-Null
  }

  $Created += 1
}

Write-Host "Created or updated $Created post-match refresh tasks."
Write-Host "Schedule source: $SchedulePath"
Write-Host "Times are stored as Eastern Time and converted to this computer's local time zone: $($LocalTimeZone.Id)."
