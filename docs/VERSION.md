# Version

## Current

- Version: `v3.6.1-cleanliness`
- Date: 2026-05-20
- Purpose: engineering-cleanliness baseline with explicit Vivado targets for
  calibration, reconstruction, FPGA demo, and ASIC skeleton synthesis; retained
  fixed-point contract, four-TB XSIM regression, CI/lint scaffolding, and
  synchronized delivery package metadata.

## Recovery Points

- Full organized snapshot: `archive/full-project-before-core-prune`
- Physical archive of files removed by `039c478`: `archive/deleted-in-039c478/`
- Physical archive of files removed by `110ef75`: `archive/deleted-in-110ef75/`
- Previous core source commit: `039c478`

## Policy

The active Vivado project should stay small. Keep only RTL/TB files required for
the reproduced digital algorithm. Files removed from active use should be placed
under `archive/` before being dropped from the main project structure.
