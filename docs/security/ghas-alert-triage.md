# GHAS alert triage

Sprint 2026-11. Each open alert is fixed in this repo or listed with the GitHub dismissal reason to apply. This document does not dismiss alerts.

| Type | Number | Rule / package | Path | Disposition | Reason |
| --- | --- | --- | --- | --- | --- |
| code-scanning | 1 | js/incomplete-multi-character-sanitization | tools/gen-icons.mjs | fixed | The generator scanned HTML comments by deleting one `<!--...-->` match; that deletion can reassemble `<!--` and a shape inside the comment was still parsed. It now finds each comment and removes it through its closer, or through end of file when the comment is unclosed. |

No alert is accepted, so no GitHub dismissal reason is recommended. Alert: https://github.com/fleethacker-data-crucible/Bowerbird/security/code-scanning/1
