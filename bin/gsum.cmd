@echo off
setlocal EnableDelayedExpansion
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\scripts\Get-GitSummary\Get-GitSummary.ps1" %*
endlocal