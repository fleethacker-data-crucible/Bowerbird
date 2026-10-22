# Bowerbird Studio

**Local-first file intelligence and screenshot renaming for Windows PowerShell 5.1 and your existing web browser.**

[Windows PowerShell CI](https://github.com/ashable2/bowerbird/actions/workflows/windows-powershell.yml) · [Source](https://github.com/ashable2/bowerbird/tree/main)

No Python, Node, npm, Git executable, or admin-installed package is required on the target workstation. The development pipeline uses Node only to check syntax on GitHub-hosted Windows runners.

## Start: the GUI, not the legacy CLI

**Double-click Start-Bowerbird.bat**. This is the supported GUI launcher, modeled on ARC/Cascade's PowerShell 5.1 -STA, -NoProfile, process-scoped execution settings and browser-native architecture. It opens **Bowerbird Studio**, not the old renamer.

The second and only other BAT launcher is Start-Bowerbird-Console.bat for the original screenshot-renaming CLI.

To select a workspace:

    Start-Bowerbird.bat -Root "C:\Users\YOURNAME\Documents\Screenshots"

If none is supplied, Studio tries Pictures, Documents, the user profile, and finally the current directory. The folder must exist. **The workspace is never created or modified at startup.**

For safe launch diagnostics:

    Start-Bowerbird.bat diagnostics

To start the server without opening a browser:

    Start-Bowerbird.bat -Root "C:\TestWorkspace" -NoBrowser

Copy the Session URL from PowerShell into your browser. It contains a private ephemeral token; don't share it in logs or screenshots. If automatic browser opening is blocked, the backend remains available and prints the manual session URL.

### Ports and workstation compatibility

Normal startup uses **pure Windows PowerShell 5.1 with .NET TcpListener on 127.0.0.1**. No C# compilation, HTTP.sys URL reservation, administrator privileges, Node, Python, or external web-server installation is required. It prefers local port **8767**, and when another app owns that port, binds an available OS-assigned port and prints/opens the actual URL. This follows ARC's auto-port approach.

    Start-Bowerbird.bat -Port 8800

-Port 0 always selects an available port. -FixedPort fails rather than switching ports. -Transport HttpListener and -Transport CompiledTcp remain available as opt-in development alternatives but are not needed for GUI launch. Process-scoped execution settings cannot override enforced Group Policy, AppLocker or WDAC rules.

### Diagnostics and troubleshooting

Startup failures remain visible in the BAT window. The browser has a **Diagnostics** button displaying safe UI button identifiers, API response codes and startup errors. Local logs live under:

    %LOCALAPPDATA%\Bowerbird\Logs

Indices, journals and plans live under:

    %LOCALAPPDATA%\Bowerbird\State

Those paths avoid writing to a possibly read-only installation folder. Logs omit request bodies, image contents, credentials and token query strings. Review diagnostics before sharing.

Run Start-Bowerbird.bat diagnostics when the GUI doesn't start. It checks required files, PowerShell parsing, a local loopback socket, state-folder writability, and effective policy without changing policy.

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
| Tests | Windows PowerShell parser check, JavaScript/DOM contract tests, smoke and real localhost HTTP API tests on both transports |

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

GitHub Actions checks PowerShell and JS/DOM syntax, startup prerequisites, both HTTP transports, port collisions, the real GUI BAT launcher, and Edge rendering when available. Windows-hosted CI cannot establish behavior under every managed workstation policy. The Studio integration test exercises authentication, indexing, search, duplicate discovery, related files, local agents, planning, apply, undo and path rejection without any AI token.

## Privacy, safety and operations

- No endpoint workaround or privilege escalation. Use only software/network paths authorized for your workstation.
- Cloud AI is disabled unless launched with `-AllowCloudAI`. Only send content authorized for the configured destination.
- API endpoints require a cryptographically generated session token, reject foreign browser origins and bind to `127.0.0.1`. Do **not** expose the service with proxies or port forwarding.
- The index may contain **plaintext extracted documents** in `Data/studio-index.json` when content indexing is enabled. `Data/` is ignored by Git.
- The journal archives previous move runs in `Data/history/`. It is not an ACID filesystem transaction and does not guarantee rollback on power loss. Keep backups of important data and test rules on copies first.
- File access is constrained to the selected workspace, with API path checks and reparse-point protections. Review local endpoint policy before handling sensitive workloads.

For the standalone intelligence CLI see [README_INTELLIGENCE.md](README_INTELLIGENCE.md). For original renamer usage see [README_MVP.md](README_MVP.md).
