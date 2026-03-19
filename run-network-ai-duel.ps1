[CmdletBinding()]
param(
  [string]$BackendUrl = 'http://localhost:8080',
  [string]$Name = '',
  [int]$CooldownSeconds = 3,
  [int]$Seed = 0,
  [int]$MaxSeconds = 120,
  [string]$Role = 'client',
  [string]$RunId = '',
  [string]$LogDir = 'debug'
)

$ErrorActionPreference = 'Stop'

$repoRoot = $PSScriptRoot
$dartDefault = 'C:\dev\flutter\bin\flutter.bat'
$dartExe = if (Test-Path $dartDefault) { $dartDefault } else { 'flutter' }

if ([string]::IsNullOrWhiteSpace($Name)) {
  $Name = "BackgammonAI-$env:COMPUTERNAME"
}
if ($Seed -le 0) {
  $Seed = Get-Random -Minimum 1 -Maximum 2147483647
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logDirectoryPath = Join-Path $repoRoot $LogDir
New-Item -ItemType Directory -Path $logDirectoryPath -Force | Out-Null
$safeName = ($Name -replace '[^a-zA-Z0-9_-]', '_').ToLowerInvariant()
$logFilePath = Join-Path $logDirectoryPath "network-ai-backgammon-$safeName-$timestamp.jsonl"
if ([string]::IsNullOrWhiteSpace($RunId)) {
  $RunId = "bgnet-$timestamp"
}

& $dartExe pub run tool\network_ai_duel_client.dart `
  --backend-url="$BackendUrl" `
  --name="$Name" `
  --cooldown-seconds=$CooldownSeconds `
  --seed=$Seed `
  --max-seconds=$MaxSeconds `
  --role="$Role" `
  --run-id="$RunId" `
  --log-file="$logFilePath"

$exitCode = $LASTEXITCODE
if ($exitCode -ne 0) {
  throw "Backgammon network AI duel client failed with exit code $exitCode."
}
