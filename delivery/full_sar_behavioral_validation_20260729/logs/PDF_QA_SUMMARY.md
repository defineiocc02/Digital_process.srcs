# PDF QA Summary

Date: 2026-07-29

Document:

```text
report/full_sar_behavioral_validation_cn.pdf
```

Checks:

- XeLaTeX compiled three times with `-halt-on-error`.
- No overfull/underfull box, undefined reference, or LaTeX package warning was
  found in the final log.
- PDF release checker: PASS.
- Page count: 9.
- Japanese-font exclusion: PASS.
- Embedded-font review: PASS; generated plot PDFs use Type 42 fonts.
- All pages were rendered with Poppler and reviewed as a contact sheet.
- No clipping, overlapping text, missing figure, or unreadable table was found.

SHA-256:

```text
992B3187449C8E5C0620FDB5AB43A80C2EB5C8AD6986FA2DE1C323255781EDA8
```
