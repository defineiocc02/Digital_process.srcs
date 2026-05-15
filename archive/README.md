# Archive

This directory keeps files that were removed from the active Vivado project during
cleanup. The archived files are versioned in Git, but they are not referenced by
`Digital_process/Digital_process.xpr`.

## Directories

- `deleted-in-039c478/`
  - Files removed when the project was pruned from the full organized snapshot.
  - Includes MATLAB scripts, legacy Vivado projects, old generated docs, helper
    scripts, backup RTL, backup testbenches, and old reports.
  - Source commit for restore: parent of `039c478`, also tagged as
    `archive/full-project-before-core-prune`.

- `deleted-in-110ef75/`
  - Files removed when the project was reduced to calibration and reconstruction
    cores only.
  - Includes the former top wrapper, SAR controller, flash decoder, virtual ADC
    model, system-level testbench, and flash decoder testbench.
  - Source commit for restore: parent of `110ef75`, commit `039c478`.

## Policy

The mainline stays small and only contains the active calibration and
reconstruction RTL plus their testbenches. Non-core files should be moved here
before removal from the active project so they remain easy to find without
depending on an external remote.
