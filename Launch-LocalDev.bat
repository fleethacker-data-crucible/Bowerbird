@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0" || exit /b 1
where powershell.exe >nul 2>&1 || (echo Windows PowerShell 5.1 is required. & exit /b 1)
if not exist "%TEMP%\Bowerbird-LocalDev" mkdir "%TEMP%\Bowerbird-LocalDev" || exit /b 1
echo [BOWERBIRD LOCAL DEV] Temporary test workspace only; cloud AI is off.
echo Workspace: %TEMP%\Bowerbird-LocalDev
REM Dev serve: stop any running Studio first (it holds the port and old code) and say what was stopped.
powershell.exe -NoProfile -NoLogo -File "%~dp0Stop-Bowerbird.ps1"
powershell.exe -NoProfile -NoLogo -STA -File "%~dp0Start-BowerbirdStudio.ps1" -Root "%TEMP%\Bowerbird-LocalDev" -LocalDev %*
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" pause
exit /b %RC%
