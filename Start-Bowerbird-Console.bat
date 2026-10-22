@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0" || (echo Cannot access Bowerbird folder & pause & exit /b 1)
REM This launcher is intentionally CLI-only; Start-Bowerbird.bat runs the GUI.
echo [Bowerbird] Legacy screenshot renamer CLI.
powershell.exe -STA -NoLogo -NoProfile -ExecutionPolicy Bypass -NoExit -File "%~dp0Start-BowerbirdMVP.ps1" %*
endlocal & exit /b %ERRORLEVEL%
