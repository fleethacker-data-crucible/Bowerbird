# Bowerbird Studio

**Local-first file intelligence for Windows PowerShell 5.1 and a modern browser.** No Node, Python, npm, Git executable, or administrator installation required at runtime.

## Launch

From the cloned or downloaded repository, in an authorized PowerShell session:

```powershell
powershell.exe -NoProfile -File .\Start-BowerbirdStudio.ps1 -Root "C:\Users\YOURNAME\Documents"
```

Studio opens a browser at `http://127.0.0.1:8767/` with a per-session access token. The listener binds only to loopback. Use `-NoBrowser` to suppress auto-launch; this requires using the launch URL/token from the local session. `-Port 8768` selects another port.

### Features

- Responsive dark browser UI with file navigation and safe text preview
- Workspace-constrained file browsing, lexical content search, index building, code statistics
- SHA-256 duplicate groups and 64-bit dHash similar-image grouping
- Basic Office OpenXML and text extraction (no OCR/PDF yet)
- JSON organization rules, proposed move review, explicit APPLY confirmation and undo journal
- Optional Arc/GenAI/Grok assistant (only with `-AllowCloudAI`; requires approved endpoints and credentials)
- Standalone legacy screenshot renamer: `Start-BowerbirdMVP.ps1`
- CLI intelligence commands: `Start-BowerbirdIntelligence.ps1`

### Example workflow

1. Launch Studio with a test folder as `-Root`.
2. Click **Build Index**, then explore **Intelligent Search**, **Duplicates**, and **Code Insights**.
3. In **Organize**, edit rules and generate a preview. Carefully inspect each destination.
4. Click **Apply Approved Plan** and type `APPLY` to move files. Use **Undo Last Apply** if needed.

### Tests

```powershell
powershell.exe -NoProfile -File .\Tests\Smoke.ps1
```

Smoke tests create and remove only a temporary directory. These tests have **not been executed on a Nautilus workstation**; review outputs and report failures for iterative fixes.

### Security notes

The server serves only its bundled static assets and local JSON APIs. It requires a session token for APIs and rejects requests with an unexpected Origin. Paths must remain within the configured root; reparse-point traversal is rejected for API-resolved paths. **Do not expose the loopback service through proxies or port forwarding.** Index files under `Data/` contain extracted text in plaintext. Do not index restricted/sensitive files without an approved handling plan. Cloud AI is disabled by default; only enable it for authorized content and approved endpoints. No bypass of endpoint restrictions is intended. Back up important files before applying rules: the journal is not an atomic transaction.

### Current implementation boundaries

The GUI, HTTP server, local index, file operations, and assistant request path are implemented in source. Streaming AI tokens, full semantic embeddings, OCR, PDF text extraction, multi-agent execution, enterprise SSO, and production-grade crash recovery remain unimplemented. The UI is a working code implementation **pending Windows runtime validation**, not a certified deployment.

See [README_INTELLIGENCE.md](README_INTELLIGENCE.md) and [README_MVP.md](README_MVP.md).
