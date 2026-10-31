# Demo walkthrough (synthetic files, no real data)

This walks through Bowerbird with invented files, and keeps everything it saves in a folder you choose, so a demo or a screen recording never touches your real Bowerbird state under `%LOCALAPPDATA%`. `Tests\DataDir.ps1` runs the commands below, so this page stays true.

## 1. Set up a demo folder

    $demo = Join-Path $env:TEMP 'bowerbird-demo'
    powershell.exe -NoProfile -File .\tools\New-DemoWorkspace.ps1 -Path (Join-Path $demo 'files')

That creates 10 synthetic files: two reports (one an exact copy of the other), notes, a little code, a CSV and three generated screenshots named like real ones (`Screenshot_2026-10-28_141502.png`). It refuses a folder that already has files. Nothing is read from this PC.

## 2. Keep state in the demo folder

Every Bowerbird entry point takes a data folder:

| How | Example |
|---|---|
| Studio | `Start-BowerbirdStudio.ps1 -Root "$demo\files" -DataDir "$demo\data"` (also `--data-dir <folder>` through the `.bat` launchers) |
| CLI | `--data-dir "$demo\data"` after the two command words |
| Either | set `BOWERBIRD_DATA_DIR` to the folder. The option wins over the variable |

With a data folder, the index, the move plan and journal go to `<folder>\State`, and logs, runtime files and feedback issues go to `<folder>\Logs`. Nothing is written under `%LOCALAPPDATA%`, and the demo run does not look for a Lazarette vault there either. Delete the folder to reset the demo. A relative folder is taken from the current directory; a drive root is refused. `Stop-Bowerbird.ps1` finds a demo Studio when `BOWERBIRD_DATA_DIR` is set in its shell.

## 3. Run it

The CLI (add `--json` for machine output):

    $b = '.\Start-Bowerbird-Console.bat'
    & $b index build --root "$demo\files" --data-dir "$demo\data" --recurse --include-content
    & $b index search --root "$demo\files" --data-dir "$demo\data" --query harbor
    & $b index duplicates --root "$demo\files" --data-dir "$demo\data"
    & $b rename preview --root "$demo\files" --data-dir "$demo\data" --path Screenshots
    & $b plan apply --root "$demo\files" --data-dir "$demo\data" --id <id from rename preview> --yes
    & $b plan undo --root "$demo\files" --data-dir "$demo\data" --yes

What to expect:

- `index build` indexes 10 files. `index search --query harbor` finds the two reports and the meeting notes.
- `index duplicates` shows one exact group: the two `q3-revenue-summary` reports.
- `rename preview` on `Screenshots` proposes new names (for example `2026-10-28_Screenshot_2026.png`) for the three screenshots and saves them as the move plan. Nothing moves yet. The demo screenshots have different dates on purpose: two screenshots from the same day currently get the same proposed name, and the second is skipped.
- `plan apply --yes` moves them; `plan undo --yes` puts every one back. Nothing is ever deleted.

Studio, with the same folders:

    powershell.exe -NoProfile -File .\Start-BowerbirdStudio.ps1 -Root "$demo\files" -DataDir "$demo\data"

Click Build Index, then search for `harbor`, run an exact duplicate scan, preview renames for the screenshots, and apply and undo them. The notice area always says what happened.

## 4. Clean up

    Remove-Item -Recurse -Force $demo

Only the demo folder holds anything; there is nothing else to remove.
