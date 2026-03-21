[CmdletBinding()]
param(
  [string]$BackendUrl = 'http://localhost:8080',
  [string]$Device = 'windows',
  [switch]$SkipBackend,
  [switch]$SkipBackendInstall,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Resolve-FlutterExe {
  param(
    [string]$Explicit = ''
  )

  if (-not [string]::IsNullOrWhiteSpace($Explicit) -and (Test-Path $Explicit)) {
    return $Explicit
  }

  $fromEnv = $env:BULLETHOLE_FLUTTER_EXE
  if (-not [string]::IsNullOrWhiteSpace($fromEnv) -and (Test-Path $fromEnv)) {
    return $fromEnv
  }

  $fromPath = Get-Command flutter -ErrorAction SilentlyContinue
  if ($null -ne $fromPath -and -not [string]::IsNullOrWhiteSpace($fromPath.Source)) {
    return $fromPath.Source
  }

  $legacy = 'C:\dev\flutter\bin\flutter.bat'
  if (Test-Path $legacy) {
    return $legacy
  }

  throw 'Flutter executable not found. Put `flutter` on PATH or set BULLETHOLE_FLUTTER_EXE.'
}

$repoRoot = $PSScriptRoot
$backendDir = Join-Path $repoRoot 'multiplayer_node_server'
$flutterExe = Resolve-FlutterExe
$backendAvailable = Test-Path $backendDir

if (-not $backendAvailable -and -not $SkipBackend) {
  Write-Warning "Backend directory not found: $backendDir. Starting app without local backend."
  $SkipBackend = $true
}

if (-not $SkipBackend) {
  $backendSteps = @()
  if (-not $SkipBackendInstall) {
    $backendSteps += "if (-not (Test-Path 'node_modules')) { npm install }"
  }
  $backendSteps += 'npm start'
  $backendCommand = ($backendSteps -join '; ')

  if ($DryRun) {
    Write-Host "[dry-run] backend command: $backendCommand"
  } else {
    Start-Process powershell `
      -WorkingDirectory $backendDir `
      -ArgumentList @(
        '-NoExit',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        $backendCommand
      ) | Out-Null
  }
}

$flutterCommand = "& '$flutterExe' run -d $Device --dart-define=DEFAULT_BACKEND_URL=$BackendUrl"

if ($DryRun) {
  Write-Host "[dry-run] flutter command: $flutterCommand"
} else {
  Start-Process powershell `
    -WorkingDirectory $repoRoot `
    -ArgumentList @(
      '-NoExit',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      $flutterCommand
    ) | Out-Null
}

Write-Host 'Launched Backholegammon dev stack.' -ForegroundColor Green
Write-Host "App: flutter run -d $Device --dart-define=DEFAULT_BACKEND_URL=$BackendUrl"
if ($SkipBackend) {
  if ($backendAvailable) {
    Write-Host 'Backend: skipped (--SkipBackend set)'
  } else {
    Write-Host 'Backend: skipped (no local backend directory in this repo)'
  }
} else {
  Write-Host 'Backend: npm start (multiplayer_node_server)'
}
