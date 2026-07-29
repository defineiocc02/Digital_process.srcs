# Version

## Current

- Version: `v3.9.2-main-unified-skill-refresh`
- Date: 2026-07-29
- Purpose: provide an independent, reproducible full-SAR behavioral loop from
  sampled input through 20 signed decisions, current-RTL foreground
  calibration, 22-decision SRM, Q8 reconstruction, and signed 16-bit decoding.
  The baseline includes 512 independent virtual chips, dynamic FFT metrics,
  full-range DNL/INL analysis, high-resolution tail review, a 32-page Chinese
  academic and industrial-maintenance report rebuilt with the latest PDF Skill,
  a Git worktree/branch audit, and a focused delivery package. The completed
  topic branch is fast-forwarded into `main`. ADCToolbox is used only as an
  MIT-licensed metrics backend.

## Recovery Points

- Full organized snapshot: `archive/full-project-before-core-prune`
- Physical archive of files removed by `039c478`: `archive/deleted-in-039c478/`
- Physical archive of files removed by `110ef75`: `archive/deleted-in-110ef75/`
- Previous core source commit: `039c478`

## Policy

The active Vivado project should stay small. Keep only RTL/TB files required for
the reproduced digital algorithm. Files removed from active use should be placed
under `archive/` before being dropped from the main project structure.
