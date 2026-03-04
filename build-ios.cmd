@echo off
setlocal
echo iOS builds require macOS + Xcode.
echo Run this on your Mac from repo root:
echo   ./build-ios.sh --no-codesign
echo or for signed IPA:
echo   ./build-ios.sh --export-options-plist ios/ExportOptions.plist
exit /b 1
