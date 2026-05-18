# Version

## Current

- Version: `v3.5.2-industrial-tb`
- Date: 2026-05-18
- Purpose: verified digital-core delivery package with industrial-grade TB
  comments, reproducible XSIM/synthesis scripts, FPGA/ASIC signoff review, and
  detailed Chinese reproduction/verification report.

## Recovery Points

- Full organized snapshot: `archive/full-project-before-core-prune`
- Physical archive of files removed by `039c478`: `archive/deleted-in-039c478/`
- Physical archive of files removed by `110ef75`: `archive/deleted-in-110ef75/`
- Previous core source commit: `039c478`

## Policy

The active Vivado project should stay small. Keep only RTL/TB files required for
the reproduced digital algorithm. Files removed from active use should be placed
under `archive/` before being dropped from the main project structure.
