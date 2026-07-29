# Version

## Current

- Version: `v3.8.0-current-calibration-validation`
- Date: 2026-07-29
- Purpose: validate the current repository on-chip foreground calibration RTL
  with an independent behavior-level RTL-equivalent model, refresh Vivado XSIM
  regression evidence, publish a Chinese academic validation report, and freeze
  a focused delivery package. External Huang/ADCToolbox/12-bit project material
  is treated as validation methodology only, not as the implemented algorithm.

## Recovery Points

- Full organized snapshot: `archive/full-project-before-core-prune`
- Physical archive of files removed by `039c478`: `archive/deleted-in-039c478/`
- Physical archive of files removed by `110ef75`: `archive/deleted-in-110ef75/`
- Previous core source commit: `039c478`

## Policy

The active Vivado project should stay small. Keep only RTL/TB files required for
the reproduced digital algorithm. Files removed from active use should be placed
under `archive/` before being dropped from the main project structure.
