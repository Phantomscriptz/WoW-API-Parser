@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0WoW_API_Workbench.ps1" -Action UI
if errorlevel 1 (
  echo.
  echo UI failed. See diagnostics\workbench.log
  pause
)
