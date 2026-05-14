# Changelog

## v3.2.0-core - 2026-05-15

- Added Git archive tag `archive/full-project-before-core-prune` for the full organized snapshot.
- Removed duplicate backup RTL/TB folders, legacy Vivado projects, MATLAB helper scripts, local reference docs, and old generated documentation from the main working tree.
- Moved `fpga_top_wrapper.sv` from `sim_1/new` to `sources_1/new`.
- Updated `Digital_process.xpr` to reference the top wrapper from the RTL source set.
- Merged duplicated P/N phase setup, SAR, and calc sequential logic in `sar_calib_ctrl_serial.sv`.
- Rewrote top-level README, MOC, architecture, verification, requirements, and project organization docs for the core-only structure.

## v3.1.0-organized - 2026-05-15

- Created the first organized repository snapshot.
- Added top-level docs and Git ignore rules.
- Archived old project folders in the working tree.
- Refactored low-bit reset initialization and parameterized selected RTL paths.
