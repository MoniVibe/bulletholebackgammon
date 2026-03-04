[CmdletBinding()]
param(
  [string]$BackendUrl = 'http://localhost:8080',
  [string]$Device = 'windows',
  [switch]$SkipBackend,
  [switch]$SkipBackendInstall,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$repoRoot = $PSScriptRoot
$backendDir = Join-Path $repoRoot 'multiplayer_node_server'
$flutterDefault = 'C:\dev\flutter\bin\flutter.bat'
$flutterExe = if (Test-Path $flutterDefault) { $flutterDefault } else { 'flutter' }

if (-not (Test-Path $backendDir)) {
  throw "Backend directory not found: $backendDir"
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

Write-Host 'Launched Bullethole Chess dev stack.' -ForegroundColor Green
Write-Host "App: flutter run -d $Device --dart-define=DEFAULT_BACKEND_URL=$BackendUrl"
if ($SkipBackend) {
  Write-Host 'Backend: skipped (--SkipBackend set)'
} else {
  Write-Host 'Backend: npm start (multiplayer_node_server)'
}
