# Version

## Current

- Version: `v3.11.0-physical-cdac-revalidation`
- Date: 2026-07-29
- Purpose: revalidate the physically grounded 6+4+5+5 segmented-CDAC mismatch
  campaign with separate ideal/no-SRM/exact-residue/deterministic-SRM/stochastic-
  SRM gates, separate full-scale and backed-off captures, 512 formal chips,
  full 16-bit static ramps, seven mismatch points, five amplitude points, and a
  deterministic replay audit. The current RTL-equivalent calibration remains
  the implementation baseline. A one-sided, non-oracle output-headroom guard
  is documented only as an analysis candidate after the symmetric normalization
  candidate was shown to create new clipping tails.
  This extends the independent, reproducible full-SAR behavioral loop from
  sampled input through 20 signed decisions, current-RTL foreground
  calibration, 22-decision SRM, Q8 reconstruction, and signed 16-bit decoding.
  The release includes a 27-page Chinese academic and industrial-maintenance
  report built with the latest PDF Skill, Python and Vivado XSIM regression,
  versioned CSV/JSON/figures, recovery archives, checksums, and a focused
  delivery package. ADCToolbox is used only as an MIT-licensed metrics backend.

## Recovery Points

- Full organized snapshot: `archive/full-project-before-core-prune`
- Physical archive of files removed by `039c478`: `archive/deleted-in-039c478/`
- Physical archive of files removed by `110ef75`: `archive/deleted-in-110ef75/`
- Previous core source commit: `039c478`

## Policy

The active Vivado project should stay small. Keep only RTL/TB files required for
the reproduced digital algorithm. Files removed from active use should be placed
under `archive/` before being dropped from the main project structure.
