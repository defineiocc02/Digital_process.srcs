# PDF QA Summary

Date: 2026-07-29

Document:

```text
report/full_sar_behavioral_validation_cn.pdf
```

Checks:

- XeLaTeX compiled three times with `-halt-on-error`.
- No overfull box, undefined reference, missing character, or package warning
  was found in the final log. Four underfull diagnostics in narrow path-table
  cells were visually inspected and do not clip or overlap content.
- `check_pdf_release.py`: PASS.
- `check_reference_style.py`: PASS after the mandated CJK ToUnicode maps were
  injected into the release PDF.
- Page count: 32.
- Japanese-font exclusion: PASS.
- Embedded-font review: PASS; the report uses FandolSong, Latin Modern, and
  Computer Modern families. Plot assets are embedded as 200 dpi PNG to prevent
  external Matplotlib font leakage.
- All 32 pages were rendered and reviewed as a contact sheet, with full-size
  review of file tables, mathematical derivations, spectrum, reproduction
  commands, and appendices.
- No clipping, overlapping text, missing figure, or unreadable table was found.
- Two complete three-pass XeLaTeX release builds with fixed
  `SOURCE_DATE_EPOCH` produced identical PDF bytes.
- The delivery-local generator resolved
  `behavior/outputs/summary.json`, and the report compiled independently from
  the package `report/` directory to the same release SHA-256.
- The synchronized latest-Skill style asset SHA-256 is
  `64E08B6C433CEE4EA480A7DC49B260939DB53D26A7E0F05C8E4AE43325082239`.

SHA-256:

```text
9F4B01E4E69AB5FE2E1230CCB57DEBF63A07ECB83540F1954D86A910D1E8D731
```
