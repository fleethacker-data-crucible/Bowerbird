@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "APP=%~dp0"
cd /d "%APP%" || (echo [Bowerbird] Cannot access the application folder. & pause & exit /b 1)
where powershell.exe >nul 2>&1 || (echo [Bowerbird] Windows PowerShell 5.1 is required. & pause & exit /b 1)
REM Standard GUI launcher modeled on ARC/Cascade: STA, NoProfile, process-scoped policy.
REM It does not override Group Policy, AppLocker, WDAC or organizational controls.
REM Studio stops itself when its browser tab closes. Options pass through:
REM   --stay     keep the server running after the tab closes
REM   --replace  stop an already running Studio without asking
REM Stop-Bowerbird.ps1 stops every running Studio from a shell.
if /I "%~1"=="diagnostics" goto DIAGNOSTICS
if /I "%~1"=="check" goto DIAGNOSTICS
if /I "%~1"=="--diagnostics" goto DIAGNOSTICS
echo.
echo =======================================
echo   BOWERBIRD STUDIO - Local File AI
echo =======================================
echo Starting the browser workspace (GUI)...
echo.
powershell.exe -STA -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%APP%Start-BowerbirdStudio.ps1" %*
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" goto ERROR
endlocal & exit /b 0

:DIAGNOSTICS
powershell.exe -STA -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%APP%Tests\Diagnose-Startup.ps1"
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" goto ERROR
endlocal & exit /b 0

:ERROR
echo.
echo [Bowerbird] GUI launch failed (exit %RC%).
echo Diagnostic logs are under %%LOCALAPPDATA%%\Bowerbird\Logs
echo Run Start-Bowerbird.bat diagnostics to diagnose the startup environment.
echo Managed security restrictions require administrator/IT approval, not workarounds.
pause
endlocal & exit /b %RC%
