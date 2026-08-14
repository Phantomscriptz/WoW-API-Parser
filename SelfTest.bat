@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0WoW_API_Workbench.ps1" -Action SelfTest
if errorlevel 1 (
  echo.
  echo Self-test failed. See diagnostics\workbench.log
  pause
)
