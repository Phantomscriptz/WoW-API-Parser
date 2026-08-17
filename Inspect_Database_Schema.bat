@echo off
setlocal
cd /d "%~dp0"
where powershell.exe >nul 2>&1
if errorlevel 1 (
    echo PowerShell is required.
    exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0WoW_API_Workbench.ps1" -Action InspectSchema
if errorlevel 1 (
    echo.
    echo Schema inspection failed. See diagnostics\database_schema_report.txt
    exit /b 1
)
echo.
echo Schema inspection complete.
echo Report: diagnostics\database_schema_report.txt
pause
