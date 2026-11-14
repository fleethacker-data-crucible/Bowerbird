# GHAS alert triage

Sprint 2026-11. Each open alert is fixed in this repo or listed with the GitHub dismissal reason to apply. This document does not dismiss alerts.

| Type | Number | Rule / package | Path | Disposition | Reason |
| --- | --- | --- | --- | --- | --- |
| code-scanning | 1 | js/incomplete-multi-character-sanitization | tools/gen-icons.mjs | fixed | The generator uses the shared fleet comment scan: `<!-->` and `<!--->` are empty comments, a comment closes on the first `-->` or `--!>`, an unclosed `<!--` drops the rest, and the scan repeats until a removal cannot reassemble `<!--`. |
| code-scanning | 2 | js/incomplete-multi-character-sanitization | Tests/GenIcons.mjs | fixed | The test repeated the one-pass comment delete to show the old result. That assertion is gone; the test checks only the comment scan. |

No alert is accepted, so no GitHub dismissal reason is recommended.

- https://github.com/fleethacker-data-crucible/Bowerbird/security/code-scanning/1
- https://github.com/fleethacker-data-crucible/Bowerbird/security/code-scanning/2
