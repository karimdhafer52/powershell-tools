@echo off
setlocal EnableDelayedExpansion
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\scripts\Show-Tree\Show-Tree.ps1" %*
endlocal