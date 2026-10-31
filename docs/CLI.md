# Bowerbird CLI and API for agents

Everything the Studio browser page can do is also a named command, `bowerbird <noun> <verb>`. Scripts and agents
can run them without a browser. This follows the fleet's "CLI and API for agents" convention (edge-ops `CONVENTIONS.md`).

The browser and the CLI share one code path. `Private\BowerbirdApi.ps1` holds the dispatcher (`Invoke-Api`), and the
Studio server and `Start-BowerbirdCli.ps1` both dot-source it. `Private\BowerbirdCommands.ps1` is the command list
that maps each name to its route.

## Running a command

    Start-Bowerbird-Console.bat <noun> <verb> [--option value ...] [--json] [--out file] [--yes] [--dry-run]
    Start-Bowerbird-Console.bat commands [--json]

The console launcher sends `commands` and the nouns below to the CLI. With no arguments, or with a folder path, it
runs the legacy screenshot renamer exactly as before. You can also call the CLI directly:

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Start-BowerbirdCli.ps1 status show --json

The CLI runs in its own process. It opens no port and starts no server.

| Option | Meaning |
| --- | --- |
| `--root <folder>` | The workspace. Default: the same as Studio (Pictures, Documents, the user profile, then the current folder). |
| `--json` | Print a JSON result instead of readable text. |
| `--out <file>` | Write the output to a file, UTF-8 with no BOM. |
| `--yes` | Required for destructive commands. Also supplies the route's `APPLY`/`UNDO` confirmation. |
| `--dry-run` | Show the route and request body, then stop without running anything. |
| `--input <file.json>` | Read request fields from a JSON object. Options on the command line override them. |
| `--allow-cloud-ai` | The same opt-in as Studio's `-AllowCloudAI`. Without it, AI commands fail. |
| `--local-dev` | Use the LocalDev state folder, as `Launch-LocalDev.bat` does. |

- Put options after the two command words.
- A flag with no value means `true` (`--recurse`); you can also write `--recurse false`.
- For a JSON option, pass the JSON itself or `@file.json` (for example `--rules @rules.json`). The file form avoids
  quoting problems in `cmd`.

State lives in the same per-user folder as Studio (`%LOCALAPPDATA%\Bowerbird\State`), one folder per workspace. An
index or move plan saved by one command is there for the next command, the next process, and the Studio page on the
same workspace.

## Output

With `--json`, every command prints one object:

    {"schema":"bowerbird.result/1","command":"bowerbird status show","ok":true,"result":{...}}
    {"schema":"bowerbird.result/1","command":"bowerbird index search","ok":false,"error":"Build an index first"}

`result` is exactly what the matching `/api` route returns to the browser. In `--json` mode, errors go to standard
output as the `ok:false` object. Otherwise they go to standard error.

`commands --json` prints `{"schema":"bowerbird.commands/1","commands":[...]}`. Each entry holds:

- `name`, `route` and `summary`;
- `inputs`, each with `flag`, `key`, `type`, `required` and `help`;
- `destructive`;
- `needs`: the state an earlier command must have made (`index`, `plan` or `journal`);
- `confirm`;
- `interactive`.

| Exit code | Meaning |
| --- | --- |
| 0 | OK |
| 1 | The command ran and failed (for example: no index yet, a path outside the workspace, AI not allowed) |
| 2 | Usage error: an unknown command or option, a missing required option, or a destructive command without `--yes` |

## Commands

| Command | Route | Inputs | Notes |
| --- | --- | --- | --- |
| `bowerbird status show` | `/api/status` | | |
| `bowerbird workspace select` | `/api/workspace/select` | `--path` (required) | destructive: discards the saved move plan |
| `bowerbird workspace browse` | `/api/workspace/browse` | | destructive; opens the Windows folder dialog |
| `bowerbird files list` | `/api/files` | `--path` | |
| `bowerbird file preview` | `/api/preview` | `--path` (required) | text files up to 256 KB |
| `bowerbird index build` | `/api/index` | `--path`, `--recurse`, `--include-content`, `--ocr` | |
| `bowerbird index search` | `/api/search` | `--query` (required) | needs index |
| `bowerbird index insights` | `/api/insights` | | needs index |
| `bowerbird index related` | `/api/related` | `--path` (required) | needs index |
| `bowerbird index duplicates` | `/api/duplicates` | `--visual` | needs index |
| `bowerbird agents run` | `/api/agents` | `--agent` (required: triage, cleanup, audit) | needs index; read-only |
| `bowerbird code stats` | `/api/code` | `--path`, `--recurse` | |
| `bowerbird rename preview` | `/api/rename-preview` | `--path`, `--recurse`, `--use-vision`, `--consent`, `--max-vision` | saves the move plan; vision needs `--allow-cloud-ai` and `--consent VISION_UPLOAD` |
| `bowerbird sidecar preview` | `/api/sidecar-preview` | `--path`, `--recurse` | saves the move plan (a capture and its sidecar are two operations); apply and undo are `plan apply` and `plan undo` |
| `bowerbird export semaphore` | `/api/export` | `--kind` (required: index, history), `--save` | read-only; `index` needs an index, `history` needs a journal; see [SEMAPHORE-EXPORT.md](SEMAPHORE-EXPORT.md) |
| `bowerbird plan create` | `/api/plan` | `--rules` (required, JSON), `--destination` | needs index; saves the move plan |
| `bowerbird plan apply` | `/api/apply` | `--id` (required) | destructive; needs plan; the id must match the saved plan |
| `bowerbird plan undo` | `/api/undo` | | destructive; needs journal |
| `bowerbird ai ask` | `/api/ai` | `--prompt` (required), `--include-index` | needs `--allow-cloud-ai` |
| `bowerbird diagnostics show` | `/api/diagnostics` | | |
| `bowerbird diagnostics health` | `/api/diagnostics/health` | | |
| `bowerbird diagnostics support` | `/api/diagnostics/support` | `--include-notes` | |
| `bowerbird diagnostics event` | `/api/client-event` | `--event`, `--target` (both required) | the page's own diagnostic events |
| `bowerbird feedback list` | `/api/feedback/list` | | |
| `bowerbird feedback create` | `/api/feedback/create` | `--kind`, `--severity`, `--feature`, `--title` (required), `--actual`, `--expected`, `--steps` | |
| `bowerbird feedback status` | `/api/feedback/status` | `--id`, `--status` (both required) | |
| `bowerbird commands list` | `/api/commands` | | the same as `commands` |

The request loop handles four browser routes itself, so they have no command:

- `/api/heartbeat`: tab presence;
- `/api/session/stop`: End session;
- `/api/media`: image and PDF bytes for preview;
- `/api/stream`: streamed AI replies. Use `ai ask` instead.

## Example: organize text files

    Start-Bowerbird-Console.bat index build --root "C:\Work\Inbox" --recurse --json
    Start-Bowerbird-Console.bat plan create --root "C:\Work\Inbox" --rules @rules.json --destination Organized --json
    Start-Bowerbird-Console.bat plan apply --root "C:\Work\Inbox" --id <id from plan create> --dry-run
    Start-Bowerbird-Console.bat plan apply --root "C:\Work\Inbox" --id <id from plan create> --yes --json
    Start-Bowerbird-Console.bat plan undo --root "C:\Work\Inbox" --yes

`rules.json`: `[{"Name":"Text","Extension":[".txt"],"Folder":"Text"}]`

## Example: rename SnapShackle captures from their OCR text

SnapShackle saves each capture as `NAME.png` plus a sidecar `NAME.png.meta.json` that holds the text its OCR found
(the contract is SnapShackle's `docs/CAPTURE-FORMAT.md`, schema `snapshackle.capture/1`). Bowerbird can rename the
pair from that text. It only proposes; you apply it through the same plan and journal as every other move.

    Start-Bowerbird-Console.bat sidecar preview --root "%LOCALAPPDATA%\SnapShackle\Captures" --json
    Start-Bowerbird-Console.bat plan apply --root "%LOCALAPPDATA%\SnapShackle\Captures" --id <id from sidecar preview> --yes
    Start-Bowerbird-Console.bat plan undo --root "%LOCALAPPDATA%\SnapShackle\Captures" --yes

In Studio, Smart Rename > Propose Names from SnapShackle Text does the preview; the same Apply button then applies it.

Rules:

- Only automatic names are renamed: `<SnapShackle|CutterMk|Lasso|SnipHero>-<yyyyMMdd>-<HHmmss>-<fff>-<8 hex>.png`.
  A name a person chose, or one this command already wrote, is left alone.
- The new name is `SnapShackle-<words>-<yyyyMMdd>-<HHmmss>-<fff>-<8 hex>.png`, so the capture stays listed in
  SnapShackle and keeps its sort order. `<words>` is at most six lowercase words (48 characters) from the first
  title-like line of the OCR text.
- The PNG and its sidecar are two operations in one plan, PNG first. The sidecar is moved, never edited, and
  nothing is deleted. A taken target name is skipped, never overwritten.
- OCR text can hold secrets. A line that mentions a password, token, key or similar, an e-mail address, a path, a
  URL, a long number or an id-like word never becomes part of a name. If no line is usable the capture is skipped
  and the reason is in `skipped`.
- A capture with no sidecar, an empty OCR field or an unknown schema major is skipped with a reason.

## The running server

While Studio is running, `GET /api/commands` returns the same `bowerbird.commands/1` list. It has the same checks as
every other `/api` route: the session token must be in `X-Bowerbird-Token`, and any `Origin` must be
`http://127.0.0.1:<port>`. The other routes stay `POST` only.

## Tests

`Tests\SidecarRename.ps1` runs in CI. It builds synthetic captures and sidecars in a temporary folder and checks the
slug rules, the plan, apply and undo through the journal, and the same flow through the CLI.

`Tests\CliParity.ps1` runs in CI. It checks that:

- every route the page calls has a command;
- every command route is in the dispatcher, and every dispatcher route has a command;
- names match `^bowerbird [a-z-]+ [a-z-]+$`;
- destructive commands exit 2 without `--yes`;
- `commands --json` has the schema;
- `--out` writes no BOM;
- the exit codes are right;
- index, plan, apply and undo work across separate processes;
- the console launcher routes commands to the CLI.

`Tests\StudioIntegration.ps1` checks the token and Origin rules on `GET /api/commands`.
