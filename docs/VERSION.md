# Version

## Current

- Version: `v3.7.0-surrogate-analysis`
- Date: 2026-05-26
- Purpose: integrate a bounded Huang 2025 calibration-convergence analysis
  model with explicit 16-bit output quantization and external-LSB noise units;
  retain the RTL/TB fixed-point baseline while documenting the remaining
  analog-to-RTL reproduction boundary.

## Recovery Points

- Full organized snapshot: `archive/full-project-before-core-prune`
- Physical archive of files removed by `039c478`: `archive/deleted-in-039c478/`
- Physical archive of files removed by `110ef75`: `archive/deleted-in-110ef75/`
- Previous core source commit: `039c478`

## Policy

The active Vivado project should stay small. Keep only RTL/TB files required for
the reproduced digital algorithm. Files removed from active use should be placed
under `archive/` before being dropped from the main project structure.
