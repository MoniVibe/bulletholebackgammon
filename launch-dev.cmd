@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0launch-dev.ps1" %*
