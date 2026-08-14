@echo off
setlocal
cd /d "%~dp0"
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Validate_Canonical_Database.ps1"
set "ERR=%ERRORLEVEL%"
echo.
if "%ERR%"=="0" (
  echo Canonical database validation PASSED.
) else (
  echo Canonical database validation FAILED with exit code %ERR%.
)
pause
exit /b %ERR%
