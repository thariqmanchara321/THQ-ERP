@echo off
setlocal EnableDelayedExpansion

:: ======================================================================
:: THQ BUSINESS - ONE-CLICK RELEASE AUTOMATION LAUNCHER
:: Double-click to launch interactive menu, or pass arguments from CLI:
::   RELEASE_THQ_BUSINESS.bat -Mode BuildOnly
::   RELEASE_THQ_BUSINESS.bat -Mode CheckRelease
::   RELEASE_THQ_BUSINESS.bat -Mode PublishQA
::   RELEASE_THQ_BUSINESS.bat -Mode ViewLatest
:: ======================================================================

set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%tools\windows_release\RELEASE_THQ_BUSINESS.ps1"

if not exist "%PS_SCRIPT%" (
    set "PS_SCRIPT=%SCRIPT_DIR%RELEASE_THQ_BUSINESS.ps1"
)
if not exist "%PS_SCRIPT%" (
    set "PS_SCRIPT=%SCRIPT_DIR%flexi_erp\tools\windows_release\RELEASE_THQ_BUSINESS.ps1"
)

if not exist "%PS_SCRIPT%" (
    echo.
    echo [ERROR] Could not find RELEASE_THQ_BUSINESS.ps1.
    echo Looked in:
    echo   %SCRIPT_DIR%tools\windows_release\RELEASE_THQ_BUSINESS.ps1
    echo   %SCRIPT_DIR%RELEASE_THQ_BUSINESS.ps1
    echo   %SCRIPT_DIR%flexi_erp\tools\windows_release\RELEASE_THQ_BUSINESS.ps1
    echo.
    pause
    exit /b 1
)

:: Direct command-line invocation if arguments were passed
if not "%~1"=="" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" %*
    set "EXIT_CODE=!ERRORLEVEL!"
    exit /b !EXIT_CODE!
)

:: Interactive execution (double-click)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -Mode Menu
set "EXIT_CODE=!ERRORLEVEL!"

if !EXIT_CODE! neq 0 (
    echo.
    echo [NOTICE] Launcher completed with exit code: !EXIT_CODE!
    pause
)

exit /b !EXIT_CODE!
