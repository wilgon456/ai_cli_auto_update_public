<#
.SYNOPSIS
  Registers the AI CLI auto updater as a Windows Scheduled Task.
.DESCRIPTION
  Creates or replaces a per-user scheduled task that runs every day at 05:00.
#>
[CmdletBinding()]
param(
  [string]$TaskName = 'AI CLI Auto Update',
  [string]$ScriptPath = $(Join-Path (Split-Path -Parent $PSScriptRoot) 'bin\update_ai_clis.ps1'),
  [string]$At = '05:00',
  [string]$Targets = $(if ($env:AI_CLI_TARGETS) { $env:AI_CLI_TARGETS } else { 'codex,agy,kimi' }),
  [int]$LogRetentionDays = $(if ($env:LOG_RETENTION_DAYS) { [int]$env:LOG_RETENTION_DAYS } else { 30 }),
  [switch]$InstallMissing
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resolvedScript = (Resolve-Path -LiteralPath $ScriptPath).Path
$scriptArgs = @(
  '-NoProfile'
  '-ExecutionPolicy'
  'RemoteSigned'
  '-File'
  "`"$resolvedScript`""
  '-Targets'
  "`"$Targets`""
  '-LogRetentionDays'
  "$LogRetentionDays"
)
if ($InstallMissing) {
  $scriptArgs += '-InstallMissing'
}

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ($scriptArgs -join ' ')
$trigger = New-ScheduledTaskTrigger -Daily -At $At
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 2)

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Description 'Daily conservative updater for installed AI coding CLIs. Missing CLIs are skipped as pass.' -Force | Out-Null
Write-Host "Registered scheduled task '$TaskName' to run daily at $At"
Write-Host "Script: $resolvedScript"
Write-Host "Targets: $Targets"
Write-Host "Log retention days: $LogRetentionDays"
Write-Host "Install missing: $InstallMissing"
