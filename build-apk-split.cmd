@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build-apk-split.ps1" %*
