@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0WoW_API_Workbench.ps1" -Action Analyze
if errorlevel 1 (
  echo.
  echo Database analysis failed. See diagnostics\workbench.log
  pause
)
