# Bowerbird — Intelligent screenshot and image renamer

PowerShell 5.1 project for local metadata-first image naming with optional approved cloud vision inference.

## Getting started

Run from Windows PowerShell 5.1:

```powershell
.\Start-BowerbirdMVP.ps1 -Path 'C:\Screenshots'
# Review dry-run results and audit logs before applying:
.\Start-BowerbirdMVP.ps1 -Path 'C:\Screenshots' -Apply
.\Start-BowerbirdMVP.ps1 -Undo
```

Use `Start-Bowerbird.bat` or `Start-Bowerbird-Console.bat` as launch alternatives when allowed by organizational policy. Review `Config/bowerbird.env.example` for provider configuration; prefer credentials managed by Arc rather than placing secrets in files.

## How it works

Pass 1 analyzes filename patterns, timestamps, and image metadata without transmitting content. Pass 2 optionally submits an image to a configured GenAI or Grok multimodal endpoint if the local result needs improvement. The resulting name is sanitized and made collision-resistant.

Renaming defaults to preview / WhatIf. The tool writes JSON audit entries and supports reversing applied renames through the audit log.

## Expansions

See `README_INTELLIGENCE.md` for separate indexing, duplicate detection, OpenXML text extraction, lexical retrieval, source-code statistics, rules, and move plans.

## Security and limitations

Only send data to endpoints authorized for the file's information classification. Approval to use PowerShell is not approval to bypass workstation security. This project is an early proof of concept; transaction recovery, model endpoint compatibility, performance, and Nautilus workstation behavior require testing.
