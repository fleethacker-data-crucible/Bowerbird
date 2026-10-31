# Bowerbird as a Semaphore data source

Bowerbird can write its index and its move history as flat JSON records. Semaphore reads them with Data > Add data (it takes any JSON file that holds one list of flat records; see Semaphore's `docs/FLEET_EXPORTS.md`), so a hoist can chart file counts by category, sizes over time, or how many files were moved and when. Nothing is sent anywhere: the file is written on this PC and you choose to add it.

    Start-Bowerbird-Console.bat export semaphore --kind index   --root "C:\Work\Inbox" --save --json
    Start-Bowerbird-Console.bat export semaphore --kind history --root "C:\Work\Inbox" --save --json

In Studio, Insights > Export for Semaphore has Export Index and Export Move History buttons; they save the file (as with `--save`) and show where it went.

`--save` writes `bowerbird-index.json` or `bowerbird-history.json` into the workspace's state folder, under `exports\` (next to the saved index; the result's `savedTo` gives the full path), and replaces the previous file of that kind. It never writes into the workspace. Without `--save` the records come back in the command result, and `--out file` writes the whole result envelope. The same route is `POST /api/export` (`{"kind":"index","save":true}`) while Studio runs. `index` needs an index (`index build`); `history` needs at least one applied plan.

## File shape

```json
{
  "schema": "bowerbird.export/1",
  "kind": "index",
  "exportedAt": "2026-10-31T20:15:00.0000000Z",
  "workspace": "Inbox",
  "count": 2,
  "records": [
    { "path": "Reports/q3.pdf", "name": "q3.pdf", "folder": "Reports", "extension": ".pdf", "category": "Documents",
      "size_bytes": 48211, "modified_utc": "2026-10-30T14:02:11.0000000Z", "sha256": "ab12...", "text_chars": 5120, "error": "" }
  ]
}
```

- `records` is the only list of objects in the file, so Semaphore reads it as the table (named after the file). Every other top-level field is a single value.
- Every record is flat: strings, numbers and booleans only. A missing value is an empty string, never `null`, so a column keeps one type.
- Paths are relative to the workspace, with `/`. A path outside the workspace keeps only its file name. The absolute workspace path is not exported; `workspace` is its folder name.
- File text is never exported, only its length (`text_chars`), because indexed text can hold sensitive content. Hashes are lower case.
- Timestamps are UTC, ISO 8601 (`2026-10-30T14:02:11.0000000Z`); Semaphore types such a column as a date.
- An empty export is refused (`Build an index first`, `No move history yet`), because Semaphore does not accept an empty list.

## Fields

`index`: one record per indexed file.

| Field | Type | Meaning |
|---|---|---|
| `path` | string | Workspace-relative path |
| `name` | string | File name |
| `folder` | string | Workspace-relative folder (empty for the workspace root) |
| `extension` | string | Lower case, with the dot |
| `category` | string | Bowerbird's category (Documents, Images, Code...); empty for a basic index |
| `size_bytes` | number | Size in bytes |
| `modified_utc` | string | Last write time |
| `sha256` | string | Content hash, lower case |
| `text_chars` | number | Length of the indexed text (0 when content indexing was off) |
| `error` | string | Why the file could not be read, or empty |

`history`: one record per journal entry, from the current journal and the earlier runs kept under `history\`, oldest first.

| Field | Type | Meaning |
|---|---|---|
| `run_id` | string | The plan id of the run |
| `created_utc` | string | When the run's journal was created |
| `moved_utc` | string | When this entry was prepared (empty if never started) |
| `status` | string | `Applied`, `Undone`, `Failed`, `Skipped`, `Prepared` or `NotStarted` |
| `source` | string | Workspace-relative path before the move |
| `destination` | string | Workspace-relative path after the move |
| `source_name` | string | File name before |
| `destination_name` | string | File name after |
| `source_folder` | string | Folder before |
| `destination_folder` | string | Folder after |
| `sha256` | string | Content hash recorded at plan time |
| `error` | string | Failure reason, or empty |
| `archived` | boolean | True for an earlier run, false for the current journal |

The machine-readable form of those tables (`Tests\SemaphoreExport.ps1` reads this block):

```json semaphore-export
{
  "schema": "bowerbird.export/1",
  "top": ["schema", "kind", "exportedAt", "workspace", "count", "records"],
  "kinds": {
    "index": {
      "path": "string", "name": "string", "folder": "string", "extension": "string", "category": "string",
      "size_bytes": "number", "modified_utc": "string", "sha256": "string", "text_chars": "number", "error": "string"
    },
    "history": {
      "run_id": "string", "created_utc": "string", "moved_utc": "string", "status": "string",
      "source": "string", "destination": "string", "source_name": "string", "destination_name": "string",
      "source_folder": "string", "destination_folder": "string", "sha256": "string", "error": "string", "archived": "boolean"
    }
  }
}
```

## Versioning

`schema` is `bowerbird.export/<major>`. Adding a field does not change the number; removing or retyping one does, and the old shape is documented alongside the new one. Semaphore ignores columns it does not use.

## Not covered

Semaphore does not refresh from this file on its own: re-run the export and add the file again. Reading the file in Semaphore itself was checked against its `FLEET_EXPORTS.md` rules (one record list, flat records), not by running Semaphore.
