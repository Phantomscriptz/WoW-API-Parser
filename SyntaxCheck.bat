@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$p='%~dp0WoW_API_Workbench.ps1'; $t=Get-Content -Raw -LiteralPath $p; [void][scriptblock]::Create($t); Write-Host 'PowerShell syntax parse: PASSED'"
if errorlevel 1 (
  echo.
  echo PowerShell syntax parse FAILED.
  pause
)
