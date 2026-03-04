[CmdletBinding()]
param(
  [int]$Games = 150,
  [int]$MaxPlies = 240,
  [int]$ConversionFailCapAdv = 5,
  [int]$MaxConversionFailures = -1,
  [int]$Seed = 0,
  [string]$LogDir = 'debug'
)

$ErrorActionPreference = 'Stop'

if ($Games -le 0) {
  throw 'Games must be greater than 0.'
}
if ($MaxPlies -le 0) {
  throw 'MaxPlies must be greater than 0.'
}
if ($ConversionFailCapAdv -le 0) {
  throw 'ConversionFailCapAdv must be greater than 0.'
}
if ($MaxConversionFailures -lt -1) {
  throw 'MaxConversionFailures must be >= -1.'
}

$repoRoot = $PSScriptRoot
$dartDefault = 'C:\dev\flutter\bin\dart.bat'
$dartExe = if (Test-Path $dartDefault) { $dartDefault } else { 'dart' }

if ($Seed -le 0) {
  $Seed = Get-Random -Minimum 1 -Maximum 2147483647
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logDirectoryPath = Join-Path $repoRoot $LogDir
New-Item -ItemType Directory -Path $logDirectoryPath -Force | Out-Null
$logFilePath = Join-Path $logDirectoryPath "ai-duel-weird-seed-$Seed-$timestamp.jsonl"

Write-Host "Running AI duel with seed: $Seed" -ForegroundColor Cyan
Write-Host "Games: $Games | MaxPlies: $MaxPlies"
Write-Host "ConversionFailCapAdv: $ConversionFailCapAdv | MaxConversionFailures: $MaxConversionFailures"
Write-Host "Log file: $logFilePath"
Write-Host ''

& $dartExe run tool\ai_duel.dart --games=$Games --max-plies=$MaxPlies --seed=$Seed --conversion-fail-cap-adv=$ConversionFailCapAdv --max-conversion-failures=$MaxConversionFailures --log-file="$logFilePath"
$exitCode = $LASTEXITCODE

if ($exitCode -ne 0) {
  throw "AI duel command failed with exit code $exitCode."
}

Write-Host ''
Write-Host 'AI duel completed successfully.' -ForegroundColor Green
