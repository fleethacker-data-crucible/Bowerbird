# Bowerbird Diagnostics & Feedback

This capability adapts Cascade's local session recorder, error logging, and support-bundle workflow to Bowerbird Studio. It runs without Python, Node, npm, an installed web server, external telemetry, or a cloud account.

## Record a reproducible problem

Open **Diagnostics & Feedback** in the sidebar. Select **Start Recording**, perform the actions that reproduce the problem, then select **Stop**. The timeline records:

- The names/identifiers of buttons and pages used.
- Local API routes, HTTP response status, latency, and 12-character request correlation ID.
- Browser exceptions and failed local requests, even when explicit recording is off.

The recorder intentionally **does not observe keystrokes or input values**. No paths from Explorer, image pixels, file content, saved passwords, request/response bodies, AI prompts, or authentication headers are gathered by the session recorder. Events are held in browser memory and disappear when the session closes unless you select **Export Session**.

Use **Mark Last Action Not Working** to prefill the issue form. When reporting a problem, supply a meaningful title, actual vs. expected behavior, and reproducible steps. Select **Save Local Issue Report** to persist it with a generated ID. The report is saved to your user-local Bowerbird installation, not pushed to any Git repository.

Issue records persist here:

    %LOCALAPPDATA%\Bowerbird\Logs\Issues\<issue-id>.json

Reports can be marked resolved and reopened. They are not automatically reported to GitHub, ChatGPT, or another external system.

## Read backend logs and health checks

The **Server Log** panel displays recent sanitized JSONL entries from:

    %LOCALAPPDATA%\Bowerbird\Logs\studio-YYYYMMDD.jsonl

Each HTTP request has a 12-character request ID that can be used to cross-reference an observed failure. The **Backend Health Checks** panel checks the local server, currently selected folder accessibility, browser assets, log presence, index existence and whether cloud AI is enabled. The AI setting is *not* a successful endpoint connectivity test; it just reports permission state.

The backend redacts sensitive field names (credentials, tokens, authorization) and normal Windows paths from exported event messages. **Redaction is a defense in depth, not a guarantee:** inspect the package before forwarding it.

## Export a support package

**Download Support Bundle (.json)** creates a local JSON download with:

- A short runtime summary: product version, Windows PowerShell version, server transport and port.
- Recent redacted backend events, response codes, and request IDs.
- Session recorder events, if you chose to start a recording.
- Locally reported issue metadata, statuses and generated IDs.

By default, descriptions and reproduction notes from manually entered reports are **not included**. To include them, check **Include descriptions and reproduction notes**, confirm your intention, and review the resulting file before sharing it.

**Copy Safe Summary** places a small non-narrative summary on the clipboard when supported by your browser. This does not transmit data.

No auto-upload, support portal account, API token or third-party issue tracker is required.

## When the local backend stops responding

If the page is still open but PowerShell stops responding, browser events are still available in memory. **Export Session** continues to work without the server.

If you attempt to **Save Local Issue Report** while the backend is unreachable, the browser creates a **download-only emergency issue JSON** containing the details you explicitly entered and available session events. Check your Downloads folder. The issue is not saved to Bowerbird's local Issues directory until the backend becomes available and you report it again. The UI labels these records **Downloaded Only** to distinguish them from persisted reports.

**Download Support Bundle** can also produce a partial browser-only package when the backend is offline. In this mode it includes session events and previously cached sanitized server entries, but cannot retrieve new log data. Manually typed notes are still excluded unless you opt in.

## If the GUI cannot launch

Run:

    Start-Bowerbird.bat diagnostics

This checks startup prerequisites without network access. If it still fails, inspect the displayed failure and the log under the user-local Logs folder. Launching in `-NoBrowser` mode can help isolate browser-opening issues:

    Start-Bowerbird.bat -NoBrowser

Copy the local Session URL from the PowerShell output into an approved browser. The URL includes an ephemeral credential. **Never post the full URL publicly.**

## Security and constraints

- User-generated reports can themselves contain sensitive information. Only enter content your environment authorizes you to store locally.
- The server listens on loopback, requires a per-session access token, rejects unexpected browser origins, and imposes size/type limits for issue submissions.
- Reports are local JSON files and are not cryptographically encrypted by Bowerbird; apply your organization's existing endpoint/data controls.
- There are no unapproved admin or execution-policy bypasses in the diagnostic API.
- Network or backend failures after page load are visible in the browser session recorder; if the server cannot accept a new report, export the memory-only session and run the launcher diagnostics.
- Tests: `Tests/StudioIntegration.ps1` validates report lifecycle and default-redacted bundles; `Tests/GuiFolderSwitch.js` exercises the live browser navigation, recording and reporting controls on a GitHub-hosted Windows runner.
