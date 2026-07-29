# Python Campaign Summary

Date: 2026-07-29

## Regression

```text
5 passed in 1.57s
```

Covered checks:

1. SRM LUT symmetry, midpoint, and endpoints.
2. Foreground calibration weight population.
3. Full conversion shape, SRM range, and monotonicity.
4. Short end-to-end dynamic and static metric flow.
5. Full-range ramp-histogram density path.

## Formal Run

```text
requested_chips = 512
completed_chips = 512
decoder_rows = 2048
workers = 6
dynamic_samples_per_chip = 8192
static_samples_per_code = 2
representative_static_samples_per_code = 8
stderr_bytes = 0
checkpoint_timestamp_span = 33.13 s
```

The same command was executed again after completion and resumed all 512
checkpoints without recomputing the chip simulations.

## Result Boundary

The static campaign intentionally records the full tail. Calibrated + SRM
missing-code statistics are median/P95/max = `0 / 4 / 18`; the high-resolution
worst representative retains `2` missing codes. No yield signoff is claimed.
