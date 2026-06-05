# Patchfly CLI installer for Windows (PowerShell).
#
# Usage (run in PowerShell as Regular user):
#   Set-ExecutionPolicy RemoteSigned -scope CurrentUser
#   iwr -UseBasicParsing 'https://raw.githubusercontent.com/fatmuh/patchfly/main/install/install.ps1'|iex
#
# Options (env vars):
#   $env:PATCHFLY_VERSION    Specific version to install (default: latest)
#   $env:PATCHFLY_INSTALL    Install location (default: $env:USERPROFILE\.patchfly\bin)
#   $env:PATCHFLY_REPO       GitHub repo (default: fatmuh/patchfly)

$ErrorActionPreference = 'Stop'

$Repo = if ($env:PATCHFLY_REPO) { $env:PATCHFLY_REPO } else { 'fatmuh/patchfly' }
$BinaryName = 'patchfly.exe'
$InstallDir = if ($env:PATCHFLY_INSTALL) { $env:PATCHFLY_INSTALL } else { Join-Path $env:USERPROFILE '.patchfly\bin' }
$Version = if ($env:PATCHFLY_VERSION) { $env:PATCHFLY_VERSION } else { 'latest' }

# ---------------------------------------------------------------------------
# Pretty output
# ---------------------------------------------------------------------------
function Info($msg)    { Write-Host "==> $msg" -ForegroundColor Cyan }
function Success($msg) { Write-Host "[OK] $msg" -ForegroundColor Green }
function Warn($msg)    { Write-Host "(!) $msg" -ForegroundColor Yellow }
function Error($msg)   { Write-Host "[X] $msg" -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------
# Detect arch
# ---------------------------------------------------------------------------
$Arch = $env:PROCESSOR_ARCHITECTURE
switch ($Arch) {
  'AMD64' { $Arch = 'x64' }
  'ARM64' { $Arch = 'arm64' }
  default { Error "Unsupported arch: $Arch" }
}
$OS = 'windows'
$Asset = "patchfly-$OS-$Arch.exe"
Info "Detected: $OS / $Arch"

# ---------------------------------------------------------------------------
# Resolve version
# ---------------------------------------------------------------------------
if ($Version -eq 'latest') {
  Info 'Resolving latest version...'
  try {
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -TimeoutSec 10
    $Version = $release.tag_name.TrimStart('v')
    Success "Latest version: v$Version"
  } catch {
    Warn 'Could not resolve latest version (no releases yet or no network).'
    $Version = '0.0.0-source'
  }
} else {
  Info "Requested version: v$Version"
}

# ---------------------------------------------------------------------------
# Set up temp dir
# ---------------------------------------------------------------------------
$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("patchfly-install-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $Tmp | Out-Null
$Downloaded = $false

try {
  # ---------------------------------------------------------------------------
  # Try downloading prebuilt binary
  # ---------------------------------------------------------------------------
  if ($Version -ne '0.0.0-source') {
    $ReleaseUrl = "https://github.com/$Repo/releases/download/v$Version/$Asset"
    Info "Trying prebuilt binary: $ReleaseUrl"

    $Target = Join-Path $Tmp $BinaryName
    try {
      [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
      Invoke-WebRequest -Uri $ReleaseUrl -OutFile $Target -UseBasicParsing -ErrorAction Stop
      if ((Get-Item $Target).Length -gt 0) {
        $Downloaded = $true
        $Size = [math]::Round((Get-Item $Target).Length / 1MB, 2)
        Success "Downloaded prebuilt binary ($Size MB)"
      }
    } catch {
      $code = $_.Exception.Response.StatusCode.value__
      Warn "Prebuilt binary not available (HTTP $code)"
    }
  }

  # ---------------------------------------------------------------------------
  # Fallback: build from source
  # ---------------------------------------------------------------------------
  if (-not $Downloaded) {
    Info 'Falling back to build-from-source...'

    $dart = Get-Command dart -ErrorAction SilentlyContinue
    if (-not $dart) {
      Error 'Dart SDK not found. Install from https://dart.dev/get-dart'
      Error 'Or wait for the first official release.'
    }
    $git = Get-Command git -ErrorAction SilentlyContinue
    if (-not $git) {
      Error 'git not found. Install git for Windows or wait for the first official release.'
    }

    Info "Cloning $Repo..."
    $RepoDir = Join-Path $Tmp 'repo'
    & git clone --depth 1 "https://github.com/$Repo.git" $RepoDir 2>&1 | Select-Object -Last 1

    Info 'Building with Dart SDK...'
    Push-Location (Join-Path $RepoDir 'cli')
    try {
      & dart pub get | Out-Null
      & dart compile exe bin/patchfly.dart -o (Join-Path $Tmp $BinaryName) | Out-Null
    } finally {
      Pop-Location
    }

    if (Test-Path (Join-Path $Tmp $BinaryName)) {
      $Downloaded = $true
      $Size = [math]::Round((Get-Item (Join-Path $Tmp $BinaryName)).Length / 1MB, 2)
      Success "Built from source ($Size MB)"
    } else {
      Error 'Build failed — see output above'
    }
  }

  # ---------------------------------------------------------------------------
  # Install
  # ---------------------------------------------------------------------------
  if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
  }
  $BinaryPath = Join-Path $InstallDir $BinaryName
  Move-Item -Force (Join-Path $Tmp $BinaryName) $BinaryPath
  Success "Installed to: $BinaryPath"

  # ---------------------------------------------------------------------------
  # PATH setup
  # ---------------------------------------------------------------------------
  $currentPath = [Environment]::GetEnvironmentVariable('Path', 'User')
  if ($currentPath -like "*$InstallDir*") {
    Success "Already in PATH - you can run: patchfly --version"
  } else {
    Warn 'Not in PATH yet. Adding to user PATH...'
    [Environment]::SetEnvironmentVariable('Path', "$currentPath;$InstallDir", 'User')
    $env:Path = "$env:Path;$InstallDir"
    Success "Added $InstallDir to user PATH (current shell updated; restart shell for persistence)"

    # Persist for new shells too
    Warn "To persist in ALL new PowerShell windows, run this once:"
    Write-Host '  [Environment]::SetEnvironmentVariable("Path", $env:Path, "User")' -ForegroundColor DarkGray
  }

  Write-Host ''
  Info 'Verify installation:'
  Write-Host "  & '$BinaryPath' --version" -ForegroundColor DarkGray
  Write-Host ''
  Info 'Quick start:'
  Write-Host '  patchfly register --email you@example.com --password yourpass' -ForegroundColor DarkGray
  Write-Host '  patchfly apps create --slug com.example.app --name "My App"' -ForegroundColor DarkGray
  Write-Host '  patchfly patch' -ForegroundColor DarkGray
}
finally {
  if (Test-Path $Tmp) { Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue }
}
