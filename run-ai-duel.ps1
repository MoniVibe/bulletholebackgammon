[CmdletBinding()]
param(
  [int]$Games = 10,
  [int]$Seed = 0,
  [int]$CooldownMs = 300,
  [int]$AiThinkMinMs = 120,
  [int]$AiThinkMaxMs = 260,
  [int]$StepMs = 20,
  [int]$MaxGameMs = 12000,
  [int]$MaxStallMs = 2200,
  [string]$RunId = ''
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

if ($Games -le 0) {
  throw 'Games must be greater than 0.'
}
$repoRoot = $PSScriptRoot
$dartExe = Resolve-FlutterExe

if ($Seed -le 0) {
  $Seed = Get-Random -Minimum 1 -Maximum 2147483647
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
if ([string]::IsNullOrWhiteSpace($RunId)) {
  $RunId = "sheshbesh-ai-$timestamp"
}

Write-Host "Running sheshbesh AI duel with seed: $Seed" -ForegroundColor Cyan
Write-Host "Games: $Games | CooldownMs: $CooldownMs"
Write-Host "AiThinkMinMs: $AiThinkMinMs | AiThinkMaxMs: $AiThinkMaxMs"
Write-Host "StepMs: $StepMs | MaxGameMs: $MaxGameMs | MaxStallMs: $MaxStallMs"
Write-Host "RunId: $RunId"
Write-Host ''

& $dartExe pub run tool\sheshbesh_ai_duel.dart `
  --games=$Games `
  --seed=$Seed `
  --cooldown-ms=$CooldownMs `
  --ai-think-min-ms=$AiThinkMinMs `
  --ai-think-max-ms=$AiThinkMaxMs `
  --step-ms=$StepMs `
  --max-game-ms=$MaxGameMs `
  --max-stall-ms=$MaxStallMs `
  --run-id="$RunId"
$exitCode = $LASTEXITCODE

if ($exitCode -ne 0) {
  throw "AI duel command failed with exit code $exitCode."
}

Write-Host ''
Write-Host 'AI duel completed successfully.' -ForegroundColor Green
