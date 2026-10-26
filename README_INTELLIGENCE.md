# Bowerbird Intelligence — PowerShell 5.1 expansion

This is an additive, dependency-free PowerShell implementation inspired by capabilities found in Czkawka (duplicate grouping), cloc (code statistics), Paperless (content tagging rules), TagSpaces (file organization), Everything (file indexing), Immich (perceptual image similarity), and MarkItDown (text extraction). **No third-party project source was copied or ported verbatim.** Existing image-renaming scripts remain intact.

## Features actually implemented
- SHA-256 exact duplicates; 64-bit image dHash similarity groups (not neural visual search)
- Open XML extraction from DOCX, PPTX and XLSX (basic text; not full document fidelity)
- Text extraction from common plain-text and source formats
- JSON index, BM25-inspired lexical retrieval (not embeddings / semantic search)
- Source-code line statistics (heuristic, not cloc-equivalent language parsing)
- JSON rules, collision-safe proposed moves, opt-in apply and reverse-order undo journal

## Usage
Run in Windows PowerShell 5.1 from this directory:

```powershell
.\Start-BowerbirdIntelligence.ps1 -Action Index -Path 'C:\Work' -Recurse
.\Start-BowerbirdIntelligence.ps1 -Action Search -Query 'design notes'
.\Start-BowerbirdIntelligence.ps1 -Action Duplicates
.\Start-BowerbirdIntelligence.ps1 -Action VisualDuplicates
.\Start-BowerbirdIntelligence.ps1 -Action CodeStats -Path 'C:\Work' -Recurse
.\Start-BowerbirdIntelligence.ps1 -Action Plan -RulesPath .\Examples\rules.json -DestinationRoot 'C:\Organized'
# Inspect Data\plan.json BEFORE proceeding
.\Start-BowerbirdIntelligence.ps1 -Action Apply -ConfirmApply
.\Start-BowerbirdIntelligence.ps1 -Action Undo
```

## Limitations and safeguards
No file deletion is implemented. Do not run Apply on sensitive or controlled files without authorization. The index stores extracted document contents **in plaintext**; protect Data/index.json and avoid indexing restricted content until a secure storage policy is established. The index is rebuilt, not incrementally maintained. Visual hashing requires System.Drawing support. PDF extraction, OCR, neural embeddings, browser GUI, cloud AI integration, advanced file tags, cleanup recipes, and native NTFS indexing are **not implemented** in this expansion. The journal is a best-effort recovery aid, not an atomic filesystem transaction; backup important files first. No tests have been run on a managed workstation.
