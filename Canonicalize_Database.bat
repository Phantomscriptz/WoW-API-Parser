@echo off
setlocal
cd /d "%~dp0"
if not exist "tools\Canonicalize_Database.ps1" (
  echo ERROR: tools\Canonicalize_Database.ps1 not found.
  pause
  exit /b 1
)
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Canonicalize_Database.ps1"
set "ERR=%ERRORLEVEL%"
echo.
if not "%ERR%"=="0" echo Canonical build FAILED with exit code %ERR%.
if "%ERR%"=="0" echo Canonical build completed successfully.
pause
exit /b %ERR%
