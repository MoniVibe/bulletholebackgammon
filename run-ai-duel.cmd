@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-ai-duel.ps1" %*
