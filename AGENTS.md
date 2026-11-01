# Agent notes

- No compatibility aliases. When a name changes, the old name is removed, never kept for compatibility. Local data is renamed by hand once.
- Every AI call goes through Fairlead (`Private/BowerbirdLlm.ps1`), with the key read from Windows Credential Manager `Fairlead/Bowerbird`. Don't add direct provider endpoints, token variables or vault reads for AI.
- Commit only as the configured git identity. Do not set `user.name` or `user.email`, do not pass `--author`, and do not add `Co-Authored-By` or "Generated with" lines or name any tool in commit messages or PR text.
- Windows PowerShell 5.1 syntax only in `.ps1` files.
