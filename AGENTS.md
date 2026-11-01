# Agent notes

- No legacy aliases. When a name changes, the old name is removed, never kept for compatibility. Local data is renamed by hand once.
- Lazarette is found only by the rule in `Private/LazaretteBridge.ps1` (`LAZARETTE_PATH`, a sibling `Lazarette` folder, `%USERPROFILE%\Projects\Lazarette`). Use only the `*-Lazarette*` function names from Lazarette docs/INTEGRATION.md.
- Commit only as the configured git identity. Do not set `user.name` or `user.email`, do not pass `--author`, and do not add `Co-Authored-By` or "Generated with" lines or name any tool in commit messages or PR text.
- Windows PowerShell 5.1 syntax only in `.ps1` files.
