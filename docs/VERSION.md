# Version

## Current

- Version: `v3.10.0-physical-cdac-mismatch-validation`
- Date: 2026-07-29
- Purpose: add a physically grounded 6+4+5+5 segmented-CDAC mismatch campaign
  with unit-cap area-law variation, bridge/parasitic matrix solving, an ideal
  16-bit 98 dB arithmetic gate, paper-faithful 22-decision stochastic SRM,
  512-chip calibration validation, and a finite-sample SRM precision study.
  This extends the independent, reproducible full-SAR behavioral loop from
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
