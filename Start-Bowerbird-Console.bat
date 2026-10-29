@echo off
setlocal EnableExtensions DisableDelayedExpansion
REM "<noun> <verb>" or "commands" runs the Studio API as a command line (docs\CLI.md); anything else is the legacy CLI.
set "BB_FIRST=%~1"
if defined BB_FIRST for %%N in (commands status workspace files file index agents code rename plan ai diagnostics feedback) do if /i "%%N"=="%BB_FIRST%" goto cli
cd /d "%~dp0" || (echo Cannot access Bowerbird folder & pause & exit /b 1)
REM This launcher is intentionally CLI-only; Start-Bowerbird.bat runs the GUI.
echo [Bowerbird] Legacy screenshot renamer CLI.
powershell.exe -STA -NoLogo -NoProfile -ExecutionPolicy Bypass -NoExit -File "%~dp0Start-BowerbirdMVP.ps1" %*
endlocal & exit /b %ERRORLEVEL%
:cli
powershell.exe -STA -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-BowerbirdCli.ps1" %*
endlocal & exit /b %ERRORLEVEL%
