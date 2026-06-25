param(
  [switch]$Publish,
  [switch]$Force
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$SchedulePath = Join-Path $ProjectRoot "data\processed\modeling\matchday_refresh_schedule.csv"
$RefreshScript = Join-Path $ProjectRoot "scripts\run_matchday_refresh.ps1"

if (-not (Test-Path $SchedulePath)) {
  throw "Refresh schedule not found at $SchedulePath. Run scripts\update_pipeline.py first."
}

if (-not (Test-Path $RefreshScript)) {
  throw "Refresh script not found at $RefreshScript."
}

$Rows = Import-Csv $SchedulePath
$Now = Get-Date

$Grouped = $Rows |
  Where-Object { $_.refresh_at_local -and ([datetime]$_.refresh_at_local) -gt $Now } |
  Group-Object refresh_at_local

$Created = 0

foreach ($Group in $Grouped) {
  $RefreshAt = [datetime]$Group.Name
  $TaskStamp = $RefreshAt.ToString("yyyyMMdd_HHmm")
  $TaskName = "LindaData_WorldCup_MatchdayRefresh_$TaskStamp"
  $Description = "Refresh World Cup prediction board before: " + (($Group.Group | Select-Object -ExpandProperty match_label) -join "; ")

  $ScriptArgs = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", "`"$RefreshScript`""
  )

  if ($Publish) {
    $ScriptArgs += "-Publish"
  }

  $Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument ($ScriptArgs -join " ")
  $Trigger = New-ScheduledTaskTrigger -Once -At $RefreshAt
  $Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Hours 2)

  if ($Force) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
  }

  Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $Action `
    -Trigger $Trigger `
    -Settings $Settings `
    -Description $Description | Out-Null

  $Created += 1
}

Write-Host "Created or updated $Created matchday refresh tasks."
