# The Vault — Audit (2026-09-24)

A combined review of `main` @ `2e902e4`, split into three reports:

1. **[UX Analysis](01-ux-report.md)**: heuristic evaluation against the core job (card dump → selects on an NLE timeline), with a prioritized roadmap.
2. **[QA Bug Report](02-qa-bug-report.md)**: 31 bugs, each with severity, confidence, file and line, and a suggested fix.
3. **[Security & Privacy Evaluation](03-security-report.md)**: threat model, 9 findings (no Critical or High), and verified good practices.

**How it was done:** one full read of the codebase that fed all three reports, plus the on-disk data, the screenshots and a Swift test that reproduced the crash. The UI was not driven directly: native-app automation wasn't available.

**Overlap:** some issues appear in more than one report, from different angles. For example, "Re-index wipes curation" is BUG-03 in QA and part of UX-03. "Corrupt index overwrite" is BUG-02 in QA and SEC-06 in security. Fixing it once closes both.

**Update (same day):** hands-on testing with computer use, synthetic test clips and Premiere Pro confirmed 8 of the static findings, withdrew 1 (an artifact of the test environment), and found 6 new bugs. That includes an intermittent heap-corruption crash (BUG-32) and random project ordering (BUG-33). Each report has an "Update: hands-on testing" section.

**Fix first:** BUG-01 / SEC-01 (crash), BUG-02 (library wipe), BUG-03 and BUG-04 (curation loss), then UX-01 and UX-02 (hand-off and filters in projects).
