param(
  [string]$At = "08:00",
  [switch]$Publish,
  [switch]$Force
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$RefreshScript = Join-Path $ProjectRoot "scripts\run_matchday_refresh.ps1"
$TaskName = "LindaData_WorldCup_DailyRefresh"

if (-not (Test-Path $RefreshScript)) {
  throw "Refresh script not found: $RefreshScript"
}

try {
  $TimeOfDay = [TimeSpan]::Parse($At, [System.Globalization.CultureInfo]::InvariantCulture)
  $RunAt = [datetime]::Today.Add($TimeOfDay)
} catch {
  throw "Use a 24-hour local time such as 08:00 or 14:30."
}

$Arguments = @(
  "-NoProfile",
  "-ExecutionPolicy",
  "Bypass",
  "-File",
  "`"$RefreshScript`""
)

if ($Publish) {
  $Arguments += "-Publish"
}

$Action = New-ScheduledTaskAction `
  -Execute "powershell.exe" `
  -Argument ($Arguments -join " ") `
  -WorkingDirectory $ProjectRoot

$Trigger = New-ScheduledTaskTrigger -Daily -At $RunAt
$Settings = New-ScheduledTaskSettingsSet `
  -AllowStartIfOnBatteries `
  -StartWhenAvailable `
  -ExecutionTimeLimit (New-TimeSpan -Hours 2) `
  -MultipleInstances IgnoreNew

$ExistingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

if ($ExistingTask -and $Force) {
  Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
  $ExistingTask = $null
}

if ($ExistingTask) {
  Set-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings | Out-Null
  Write-Host "Updated daily refresh task '$TaskName' for $($RunAt.ToString('HH:mm')) local time."
} else {
  Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $Action `
    -Trigger $Trigger `
    -Settings $Settings `
    -Description "Refresh and optionally publish the World Cup 2026 prediction site each day." | Out-Null
  Write-Host "Created daily refresh task '$TaskName' for $($RunAt.ToString('HH:mm')) local time."
}
