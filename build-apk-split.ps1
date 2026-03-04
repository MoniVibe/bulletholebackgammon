[CmdletBinding()]
param(
  [switch]$Clean = $false,
  [string]$FlutterExe = ''
)

$ErrorActionPreference = 'Stop'

$repoRoot = $PSScriptRoot
$flutterDefault = 'C:\dev\flutter\bin\flutter.bat'

if ($FlutterExe -and $FlutterExe.Trim().Length -gt 0) {
  $flutter = $FlutterExe
} elseif (Test-Path $flutterDefault) {
  $flutter = $flutterDefault
} else {
  $flutter = 'flutter'
}

if ($Clean) {
  Write-Host 'Running flutter clean...' -ForegroundColor Cyan
  & $flutter clean
  if ($LASTEXITCODE -ne 0) {
    throw "flutter clean failed with exit code $LASTEXITCODE."
  }
}

Write-Host 'Running flutter pub get...' -ForegroundColor Cyan
& $flutter pub get
if ($LASTEXITCODE -ne 0) {
  throw "flutter pub get failed with exit code $LASTEXITCODE."
}

Write-Host 'Building split-ABI release APKs...' -ForegroundColor Cyan
& $flutter build apk --release --split-per-abi
if ($LASTEXITCODE -ne 0) {
  throw "flutter build apk --release --split-per-abi failed with exit code $LASTEXITCODE."
}

$apkDir = Join-Path $repoRoot 'build\app\outputs\flutter-apk'
$apkNames = @(
  'app-armeabi-v7a-release.apk',
  'app-arm64-v8a-release.apk',
  'app-x86_64-release.apk'
)

Write-Host ''
Write-Host 'Split APK outputs:' -ForegroundColor Green
foreach ($apkName in $apkNames) {
  $apkPath = Join-Path $apkDir $apkName
  if (-not (Test-Path $apkPath)) {
    Write-Host "  MISSING: $apkPath" -ForegroundColor Yellow
    continue
  }

  $file = Get-Item $apkPath
  $sha256 = (Get-FileHash $apkPath -Algorithm SHA256).Hash
  Write-Host "  $($file.FullName)"
  Write-Host "    size: $($file.Length) bytes"
  Write-Host "    sha256: $sha256"
}

Write-Host ''
Write-Host 'Done.' -ForegroundColor Green
