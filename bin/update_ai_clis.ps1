<#
.SYNOPSIS
  Updates installed AI coding CLIs on Windows.
.DESCRIPTION
  Conservative updater for Codex CLI, Claude Code, and Gemini CLI.
  Missing CLIs/packages are treated as pass/skip, not failures.
#>
[CmdletBinding()]
param(
  [Alias('Check')]
  [switch]$DryRun,
  [string]$LogDir = $(if ($env:LOG_DIR) { $env:LOG_DIR } else { Join-Path $env:USERPROFILE '.ai-cli-auto-update\logs' })
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-Timestamp {
  return (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
}

function Ensure-Directory([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

Ensure-Directory $LogDir
$logFile = Join-Path $LogDir ("update-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$latestLog = Join-Path $LogDir 'latest.log'

Start-Transcript -Path $logFile -Force | Out-Null
try {
  Copy-Item -LiteralPath $logFile -Destination $latestLog -Force -ErrorAction SilentlyContinue

  $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
  $userPart = if ($identity -and $identity.User) { $identity.User.Value -replace '[^A-Za-z0-9._-]', '-' } else { $env:USERNAME -replace '[^A-Za-z0-9._-]', '-' }
  $mutexName = "Local\ai-cli-auto-update-$userPart"
  $mutex = [System.Threading.Mutex]::new($false, $mutexName)
  $hasLock = $false
  try {
    $hasLock = $mutex.WaitOne(0)
    if (-not $hasLock) {
      Write-Host "[$(Get-Timestamp)] another update run is already active"
      exit 0
    }

    $script:failures = New-Object System.Collections.Generic.List[string]

    function Get-CommandPath([string]$Name) {
      $cmd = Get-Command $Name -ErrorAction SilentlyContinue
      if ($cmd) { return $cmd.Source }
      return $null
    }

    function Write-Version([string]$Name) {
      $path = Get-CommandPath $Name
      if ($path) {
        Write-Host "${Name}:"
        try { & $Name --version 2>&1 | Select-Object -First 1 | ForEach-Object { Write-Host "  $_" } } catch { Write-Host "  version check failed: $($_.Exception.Message)" }
        Write-Host "  path: $path"
      } else {
        Write-Host "${Name}: not installed"
      }
    }

    function Test-NpmGlobalPackage([string]$Package) {
      $npm = Get-CommandPath 'npm'
      if (-not $npm) { return $false }
      & npm list -g --depth=0 $Package *> $null
      return ($LASTEXITCODE -eq 0)
    }

    function Invoke-Step([string]$Name, [scriptblock]$Action) {
      Write-Host ""
      Write-Host "== $Name =="
      if ($DryRun) {
        Write-Host "dry-run: skipped $Name"
        return
      }
      try {
        & $Action
        Write-Host "✓ $Name ok"
      } catch {
        Write-Host "✗ $Name failed: $($_.Exception.Message)"
        $script:failures.Add($Name) | Out-Null
      }
    }

    function Pass-Missing([string]$Tool, [string]$Reason) {
      Write-Host "pass: $Tool not installed or not managed here ($Reason)"
    }

    function Update-NpmPackage([string]$Package) {
      if (-not (Get-CommandPath 'npm')) { throw 'npm is not installed' }
      & npm install -g "$Package@latest"
      if ($LASTEXITCODE -ne 0) { throw "npm install failed for $Package with exit code $LASTEXITCODE" }
    }

    Write-Host "[$(Get-Timestamp)] AI CLI update started"
    Write-Host "host=$env:COMPUTERNAME user=$env:USERNAME dry_run=$DryRun"

    Write-Host ""
    Write-Host "== before versions =="
    Write-Version codex
    Write-Version claude
    Write-Version gemini

    if (Test-NpmGlobalPackage '@openai/codex') {
      Invoke-Step 'codex via npm' { Update-NpmPackage '@openai/codex' }
    } elseif (-not (Get-CommandPath 'codex')) {
      Pass-Missing 'codex' 'command not found and npm global package not installed'
    } else {
      Pass-Missing 'codex' 'command exists but no supported Windows package manager was detected'
    }

    if (Test-NpmGlobalPackage '@anthropic-ai/claude-code') {
      Invoke-Step 'claude-code via npm' { Update-NpmPackage '@anthropic-ai/claude-code' }
      $claudeUpdated = $true
    } elseif (-not (Get-CommandPath 'claude')) {
      Pass-Missing 'claude' 'command not found and npm global package not installed'
      $claudeUpdated = $false
    } else {
      $claudeUpdated = $false
    }
    if ((-not $claudeUpdated) -and (Get-CommandPath 'claude')) {
      Invoke-Step 'claude built-in update' { & claude update; if ($LASTEXITCODE -ne 0) { throw "claude update exit code $LASTEXITCODE" } }
    }

    if (Test-NpmGlobalPackage '@google/gemini-cli') {
      Invoke-Step 'gemini-cli via npm' { Update-NpmPackage '@google/gemini-cli' }
    } elseif (-not (Get-CommandPath 'gemini')) {
      Pass-Missing 'gemini' 'command not found and npm global package not installed'
    } else {
      Pass-Missing 'gemini' 'command exists but no supported Windows package manager was detected'
    }

    Write-Host ""
    Write-Host "== after versions =="
    Write-Version codex
    Write-Version claude
    Write-Version gemini

    Write-Host ""
    Write-Host "log_file=$logFile"

    if ($script:failures.Count -gt 0) {
      Write-Host "[$(Get-Timestamp)] AI CLI update finished with failures: $($script:failures -join ', ')"
      exit 1
    }

    Write-Host "[$(Get-Timestamp)] AI CLI update finished successfully"
  } finally {
    if ($hasLock) { $mutex.ReleaseMutex() | Out-Null }
    $mutex.Dispose()
  }
} finally {
  Stop-Transcript | Out-Null
  Copy-Item -LiteralPath $logFile -Destination $latestLog -Force -ErrorAction SilentlyContinue
}
