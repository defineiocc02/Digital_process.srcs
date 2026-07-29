# PDF QA Summary

Date: 2026-07-29

Report:

- `docs/current_calibration_validation_report_cn.pdf`

Build:

- XeLaTeX, 3 passes.
- Blocking log scan: PASS.
- Release checker: PASS.
- Pages: 7.
- SHA-256: `AD3211EB6F7FB82D5266801FC015C1BAFB60218917849C4D9FCF2AFF4F2A8C70`.

Mechanical gates:

- No `Overfull` boxes in final log.
- No unresolved references detected by the release checker.
- No missing CJK glyph warnings detected.
- Fonts are embedded according to `pdffonts`.

Visual QA:

- Rendered all 7 pages at 150 dpi.
- Inspected final contact sheet.
- No blank page, missing figure, clipping, or obvious overlap observed.

External MiKTeX notes:

- MiKTeX printed elevated-privilege and update-check notices. These are local toolchain maintenance notices, not report-content failures.
