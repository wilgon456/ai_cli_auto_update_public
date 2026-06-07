<#
.SYNOPSIS
  Updates installed AI coding CLIs on Windows.
.DESCRIPTION
  Conservative updater for selected AI coding CLIs.
  Missing CLIs/packages are treated as pass/skip, not failures.
#>
[CmdletBinding()]
param(
  [Alias('Check')]
  [switch]$DryRun,
  [string]$LogDir = $(if ($env:LOG_DIR) { $env:LOG_DIR } else { Join-Path $env:USERPROFILE '.ai-cli-auto-update\logs' }),
  [int]$LogRetentionDays = $(if ($env:LOG_RETENTION_DAYS) { [int]$env:LOG_RETENTION_DAYS } else { 30 }),
  [int]$VersionTimeoutSeconds = $(if ($env:VERSION_TIMEOUT_SECONDS) { [int]$env:VERSION_TIMEOUT_SECONDS } else { 10 }),
  [string]$Targets = $(if ($env:AI_CLI_TARGETS) { $env:AI_CLI_TARGETS } else { 'codex,agy,kimi' }),
  [switch]$InstallMissing
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

function Invoke-WithTimeout([string]$Name, [string[]]$Arguments, [int]$TimeoutSeconds) {
  $cmd = Get-Command $Name -ErrorAction Stop
  $psi = [System.Diagnostics.ProcessStartInfo]::new()
  $psi.FileName = $cmd.Source
  foreach ($arg in $Arguments) {
    [void]$psi.ArgumentList.Add($arg)
  }
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.UseShellExecute = $false

  $process = [System.Diagnostics.Process]::new()
  $process.StartInfo = $psi
  [void]$process.Start()
  if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
    try { $process.Kill($true) } catch { }
    return [pscustomobject]@{ ExitCode = 124; Output = "TIMEOUT after ${TimeoutSeconds}s" }
  }

  $output = @($process.StandardOutput.ReadToEnd(), $process.StandardError.ReadToEnd()) -join ''
  return [pscustomobject]@{ ExitCode = $process.ExitCode; Output = $output }
}

function Remove-OldLogs([string]$Path, [int]$RetentionDays) {
  if ($DryRun) {
    Write-Host 'dry-run: skipped log cleanup'
    return
  }
  if ($RetentionDays -lt 0) {
    Write-Host "warn: invalid LogRetentionDays=$RetentionDays; skipping log cleanup"
    return
  }
  if ($RetentionDays -eq 0) {
    Write-Host 'pass: log cleanup disabled'
    return
  }
  $cutoff = (Get-Date).AddDays(-$RetentionDays)
  $logs = @(Get-ChildItem -LiteralPath $Path -Filter 'update-*.log' -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cutoff })
  foreach ($log in $logs) {
    Remove-Item -LiteralPath $log.FullName -Force -ErrorAction SilentlyContinue
  }
  Write-Host "log cleanup: removed $($logs.Count) update logs older than ${RetentionDays}d"
}

function Test-TargetEnabled([string]$Name) {
  $selected = @($Targets -split ',' | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ })
  return ($selected -contains 'all') -or ($selected -contains $Name.ToLowerInvariant())
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
        $result = Invoke-WithTimeout $Name @('--version') $VersionTimeoutSeconds
        $firstLine = (($result.Output -split "`r?`n") | Where-Object { $_ } | Select-Object -First 1)
        if ($result.ExitCode -eq 124) {
          Write-Host "${Name}: TIMEOUT after ${VersionTimeoutSeconds}s"
        } elseif ($result.ExitCode -ne 0) {
          $detail = if ($firstLine) { ": $firstLine" } else { '' }
          Write-Host "${Name}: ERROR rc=$($result.ExitCode)$detail"
        } else {
          $versionLine = if ($firstLine) { $firstLine } else { 'unknown' }
          Write-Host "${Name}: $versionLine"
        }
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

    function Install-NpmPackage([string]$Package) {
      Update-NpmPackage $Package
    }

    function Update-AgyCli {
      if (-not (Get-CommandPath 'agy')) { throw 'agy is not installed' }
      $result = Invoke-WithTimeout 'agy' @('update') 300
      if ($result.Output) { Write-Host $result.Output.TrimEnd() }
      if ($result.ExitCode -ne 0) { throw "agy update failed with exit code $($result.ExitCode)" }
    }

    function Update-KimiCli {
      if (Test-NpmGlobalPackage '@moonshot-ai/kimi-code') {
        Update-NpmPackage '@moonshot-ai/kimi-code'
      } elseif (Get-CommandPath 'kimi') {
        Write-Host 'kimi command exists but is not npm-managed; skipping unattended update'
        Write-Host '      reinstall/update with npm for automation: npm install -g @moonshot-ai/kimi-code@latest'
      } elseif ($InstallMissing) {
        Install-NpmPackage '@moonshot-ai/kimi-code'
      } else {
        Pass-Missing 'kimi' 'command not found and npm global package not installed'
      }
    }

    Write-Host "[$(Get-Timestamp)] AI CLI update started"
    Write-Host "host=$env:COMPUTERNAME user=$env:USERNAME dry_run=$DryRun targets=$Targets install_missing=$InstallMissing"
    Remove-OldLogs $LogDir $LogRetentionDays

    Write-Host ""
    Write-Host "== before versions =="
    if (Test-TargetEnabled 'codex') { Write-Version codex }
    if (Test-TargetEnabled 'agy') { Write-Version agy }
    if (Test-TargetEnabled 'kimi') { Write-Version kimi }

    if (Test-TargetEnabled 'codex') {
      if (Test-NpmGlobalPackage '@openai/codex') {
        Invoke-Step 'codex via npm' { Update-NpmPackage '@openai/codex' }
      } elseif (-not (Get-CommandPath 'codex') -and $InstallMissing) {
        Invoke-Step 'codex via npm install' { Install-NpmPackage '@openai/codex' }
      } elseif (-not (Get-CommandPath 'codex')) {
        Pass-Missing 'codex' 'command not found and npm global package not installed'
      } else {
        Pass-Missing 'codex' 'command exists but no supported Windows package manager was detected'
      }
    }

    if (Test-TargetEnabled 'agy') {
      if (Get-CommandPath 'agy') {
        Invoke-Step 'antigravity cli via agy' { Update-AgyCli }
      } else {
        Pass-Missing 'agy' 'command not found'
      }
    }

    if (Test-TargetEnabled 'kimi') {
      Invoke-Step 'kimi code via npm' { Update-KimiCli }
    }

    Write-Host ""
    Write-Host "== after versions =="
    if (Test-TargetEnabled 'codex') { Write-Version codex }
    if (Test-TargetEnabled 'agy') { Write-Version agy }
    if (Test-TargetEnabled 'kimi') { Write-Version kimi }

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
