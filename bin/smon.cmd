@echo off
setlocal EnableDelayedExpansion
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\scripts\Show-Monitor\Show-Monitor.ps1" %*
endlocal