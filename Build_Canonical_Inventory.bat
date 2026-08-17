@echo off
setlocal
cd /d "%~dp0"
where powershell.exe >nul 2>&1
if errorlevel 1 (
    echo PowerShell is required.
    exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Build_Canonical_Inventory.ps1"
if errorlevel 1 (
    echo.
    echo Canonical inventory build failed. See diagnostics\canonical_inventory_validation.txt
    exit /b 1
)
echo.
echo Canonical inventory build complete.
echo Output: output\canonical_api_inventory.json
echo Report: diagnostics\canonical_inventory_validation.txt
pause
