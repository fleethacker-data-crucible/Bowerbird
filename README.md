# Bowerbird Studio

**Local-first file intelligence and screenshot renaming for Windows PowerShell 5.1 and your existing web browser.**

[Windows PowerShell CI](https://github.com/ashable2/bowerbird/actions/workflows/windows-powershell.yml) · [Source](https://github.com/ashable2/bowerbird/tree/main)

No Python, Node, npm, Git executable, or admin-installed package is required on the target workstation. The development pipeline uses Node only to check syntax on GitHub-hosted Windows runners.

## Start

Download/clone the repository and run from an authorized PowerShell session:

```powershell
powershell.exe -NoProfile -File .\Start-BowerbirdStudio.ps1 -Root "C:\Users\YOURNAME\Documents"
```

The script opens the browser at `http://127.0.0.1:8767/` with a random per-session token. If browser launch is blocked:

```powershell
powershell.exe -NoProfile -File .\Start-BowerbirdStudio.ps1 -Root "C:\TestWorkspace" -NoBrowser -Port 8768
```

Copy the **Session URL** printed in PowerShell. The UI and API share the loopback-only port. `Ctrl+C` stops the service. `HttpListener` may require an authorized local HTTP URL reservation in some managed Windows configurations; contact IT rather than elevating permissions or bypassing endpoint controls.

## What is implemented

| Area | Functionality |
| --- | --- |
| Explorer | Folder navigation, metadata, text preview, local image preview and browser PDF viewer |
| Smart Rename | Screenshot/image analysis using metadata and filename patterns, optional AI vision, preview, consented apply, undo |
| Smart Index | SHA-256, image dHash, categories, metadata, optional full-text and optional OCR |
| Search | BM25-inspired token scoring with cached per-document frequencies, file name boost |
| Related Files | Local Jaccard-style lexical similarity for discovering related indexed files |
| Duplicates | Exact SHA-256 groups and near-duplicate image hash groups |
| Organization | JSON rules for extensions, names, content and file sizes, collision reporting, approval before applying |
| Journaling | Per-step durable journal, archive of previous runs, source hash preconditions and checked undo |
| Insights | Category inventory, indexed bytes, duplicate groups, extraction failures |
| Local Agents | Read-only organization, duplication, and index-quality analysis; usable without cloud AI |
| AI Chat | Optional Arc/GenAI/Grok integration, streamed browser output when provider supports SSE; fallback JSON responses |
| Code Insights | Language and line statistics by extension |
| Tests | Windows PowerShell parser check, JavaScript parser check, smoke and real localhost HTTP API tests |

### Important implementation distinctions

- **PDF**: Browsing works through the browser's native PDF viewer. Local PDF text extraction is best-effort for uncompressed and FlateDecode text streams; this is **not** a full PDF parser.
- **OCR**: If an approved `tesseract.exe` is already available on PATH, enable OCR when indexing. Nothing is auto-installed.
- **AI vision**: The legacy CLI now requires `-AllowVision` and Studio requires both `-AllowCloudAI` and a separate explicit vision consent. No images are uploaded by ordinary indexing or local rename preview.
- **Streaming**: The SSE bridge supports compatible providers; endpoints which decline streaming may return a complete JSON response. Model authentication still needs working approved credentials / Arc integration.
- **Agents**: The local agents are deterministic and read-only. They are not autonomous LLM tool-call agents.
- **Search**: Related-file matching is lexical, not neural embeddings. There is no on-device LLM included.

## Recommended workflows

**Explore and search**: Launch with a disposable or approved workspace, click *Build Index*, optionally enable content indexing, then use Search, Duplicates, or Insights & Agents.

**Rename screenshots**: Open the target folder in Explorer, select *Smart Rename*, optionally enable approved AI vision, then *Generate Rename Proposals*. Review the confidence and destination of each proposal before entering `APPLY`.

**Organize files**: Edit the JSON rules in *Organize*, generate a plan and inspect every proposed move. `APPLY` is required to modify files. The *Undo Last Apply* button checks source/destination and checksum preconditions before restoration.

**Legacy CLI**:

```powershell
powershell.exe -NoProfile -File .\Start-BowerbirdMVP.ps1 -Path "C:\TestImages"
powershell.exe -NoProfile -File .\Start-BowerbirdMVP.ps1 -Path "C:\TestImages" -AllowVision -MaxVision 5
powershell.exe -NoProfile -File .\Start-BowerbirdMVP.ps1 -Path "C:\TestImages" -Apply
```

The default CLI behavior is preview-only and offline. Use cloud vision only on data approved for the selected endpoint.

## Testing

```powershell
powershell.exe -NoProfile -File .\Tests\Smoke.ps1
powershell.exe -NoProfile -File .\Tests\StudioIntegration.ps1
```

GitHub Actions also runs the parser, JS syntax and both tests on a Windows runner for each push to main. The Studio integration test exercises authentication, indexing, search, duplicate discovery, related files, local agents, planning, apply, undo and path rejection without any AI token.

## Privacy, safety and operations

- No endpoint workaround or privilege escalation. Use only software/network paths authorized for your workstation.
- Cloud AI is disabled unless launched with `-AllowCloudAI`. Only send content authorized for the configured destination.
- API endpoints require a cryptographically generated session token, reject foreign browser origins and bind to `127.0.0.1`. Do **not** expose the service with proxies or port forwarding.
- The index may contain **plaintext extracted documents** in `Data/studio-index.json` when content indexing is enabled. `Data/` is ignored by Git.
- The journal archives previous move runs in `Data/history/`. It is not an ACID filesystem transaction and does not guarantee rollback on power loss. Keep backups of important data and test rules on copies first.
- File access is constrained to the selected workspace, with API path checks and reparse-point protections. Review local endpoint policy before handling sensitive workloads.

For the standalone intelligence CLI see [README_INTELLIGENCE.md](README_INTELLIGENCE.md). For original renamer usage see [README_MVP.md](README_MVP.md).
