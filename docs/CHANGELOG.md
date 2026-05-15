# Changelog

## v3.3.1-archive - 2026-05-15

- Restored previously removed files into tracked archive directories.
- Added `archive/deleted-in-039c478/` for MATLAB, legacy Vivado projects, backup files, old docs, scripts, and reports removed by the first prune.
- Added `archive/deleted-in-110ef75/` for former top/SAR/Flash/virtual ADC files and duplicate testbenches removed by the minimal-core prune.
- Updated `.gitignore` so archive contents are versioned.
- Kept active RTL logic unchanged.

## v3.3.0-minimal - 2026-05-15

- Reduced mainline to two RTL files: calibration and reconstruction.
- Kept only two corresponding testbenches.
- Removed `fpga_top_wrapper`, `sar_adc_controller`, `flash_decoder_adder`, `virtual_adc_phy`.
- Removed system-level and flash decoder testbenches.
- Updated `Digital_process.xpr` to reference only minimal RTL/TB files.
- Further merged duplicated P/N DAC drive logic inside `sar_calib_ctrl_serial`.

## v3.2.0-core - 2026-05-15

- Added Git archive tag `archive/full-project-before-core-prune` for the full organized snapshot.
- Removed duplicate backup RTL/TB folders, legacy Vivado projects, MATLAB helper scripts, local reference docs, and old generated documentation from the main working tree.
- Moved `fpga_top_wrapper.sv` from `sim_1/new` to `sources_1/new`.
- Updated `Digital_process.xpr` to reference the top wrapper from the RTL source set.
- Merged duplicated P/N phase setup, SAR, and calc sequential logic in `sar_calib_ctrl_serial.sv`.

## v3.1.0-organized - 2026-05-15

- Created the first organized repository snapshot.
- Added top-level docs and Git ignore rules.
- Archived old project folders in the working tree.
- Refactored low-bit reset initialization and parameterized selected RTL paths.
