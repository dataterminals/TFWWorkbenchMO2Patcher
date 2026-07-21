@echo off
REM ---------------------------------------------------------------------------
REM  Double-clickable wrapper for Patch-TFWWorkbench.ps1.
REM
REM  Windows defaults to an execution policy of Restricted, and any file you
REM  downloaded carries a mark-of-the-web flag, so .ps1 files will NOT run for a
REM  normal user - they get "cannot be loaded because running scripts is
REM  disabled on this system". -ExecutionPolicy Bypass covers both, for this one
REM  process only. Nothing about your system is changed.
REM ---------------------------------------------------------------------------
setlocal
cd /d "%~dp0"

if "%~1"=="" (
    echo.
    echo   TFWWorkbench MO2 Patcher
    echo   ------------------------
    echo   Drag your MO2 ^"mods^" folder onto this .bat, or paste the path below.
    echo   It looks like:  H:\MO2Instance_ModData\ForeverWinter\mods
    echo.
    set /p MODSPATH="   mods folder: "
) else (
    set "MODSPATH=%~1"
)

if "%MODSPATH%"=="" (
    echo   No path given. Nothing done.
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Patch-TFWWorkbench.ps1" -ModsPath "%MODSPATH%"

echo.
pause
