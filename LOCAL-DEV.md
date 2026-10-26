# BOWERBIRD — local development (no smart card)

Run `Launch-LocalDev.bat` from this repository on your **personal Windows PC** after checking out the feature branch. Do not use on a managed system to defeat organizational security policy.

## What it does

- Prerequisite: Windows PowerShell 5.1.
- Startup: Uses an isolated %TEMP%\Bowerbird-LocalDev workspace and defaults to local-only intelligence. Make and delete test files there.
- Boundary: Selecting production data or enabling AI explicitly is outside this safe launcher. Do not enable cloud AI for sensitive files.
- Lifecycle: the launcher first runs `Stop-Bowerbird.ps1` and prints any server it stopped, so an old Studio never holds the port or serves stale code. Closing the tab stops the dev server; pass `--stay` to keep it running.
- Diagnostics / manual check: `powershell.exe -NoProfile -File Start-BowerbirdStudio.ps1 -Root "$env:TEMP\Bowerbird-LocalDev"`.

## Workflow

```powershell
git fetch origin
git switch <feature-branch>
.\Launch-LocalDev.bat
```

The original production launcher and authentication checks remain unchanged. Mock, local, or offline sessions are **not** authenticated operational sessions, and must not contain sensitive or regulated data, real credentials, or production personal data.

When stable, remove `Launch-LocalDev.bat` (and the Lazarette mock files where applicable) from the release branch. Do not deploy them as a means of avoiding smart card sign-in or authorization for live systems.
