# Changelog

## v3.7.0-surrogate-analysis - 2026-05-26

- Added `analysis/surrogate/replicate_huang2025_calibration_convergence.py`
  for reproducible, paired Monte Carlo study of calibration-noise averaging.
- Corrected the proposed surrogate by quantizing performance evaluation to an
  explicit 16-bit output domain and injecting paper-referenced noise in
  external output-LSB units.
- Added proxy-domain and direct RTL-Q8 saturation diagnostics so the
  reconstruction-derived table is not presented as a verified analog SAR
  decision vector.
- Added a detailed Chinese code-review and model-integration report, and kept
  generated CSV/JSON/PNG outputs outside Git.
- Corrected stale `Q18.12` comments in the calibration controller mirrors to
  the active Q8 fixed-point contract; no RTL behavior changed.

## v3.6.1-cleanliness - 2026-05-20

- Added `build_asic_skeleton` so `sar_adc_digital_top.sv` is covered by the
  authoritative Vivado batch build flow.
- Updated repository consistency checks and README/verification metadata for
  all four build targets.
- Cleaned trailing whitespace in active documentation and RTL mirrors.
- Added LaTeX auxiliary-file ignore rules for local paper drafting artifacts.

## v3.5.4-fixed-point-contract - 2026-05-18

- Added `docs/FIXED_POINT_CONTRACT.md` to define Q8 units, reconstruction
  arithmetic, SRM residue semantics, binary-normalized TB scale, and split-cap
  Q8 weight contract.
- Renamed the reconstruction smoke test to `tb_sar_recon_binary_norm.sv` and
  replaced the historical `<< 4` magic scale with `BINARY_NORM_SHIFT`.
- Added `tb_recon_q8_split_weights.sv` to verify Q8 split-cap weights,
  `srm_residue`, and `sar_reconstruction` against a bit-exact manual model.
- Updated XSIM regression scripts and Vivado project metadata for the expanded
  four-testbench verification set.

## v3.5.3-gap-analysis - 2026-05-18

- Added a detailed Chinese technical gap analysis comparing the delivered RTL/TB
  against Huang's original split-sampling SAR ADC algorithm boundary.
- Documented the reproduction distance for calibration, SRM residue estimation,
  digital reconstruction, MATLAB/model differences, and remaining FPGA/ASIC
  signoff work.
- Updated the main README, MOC, version metadata, and delivery package links.
- No RTL or TB behavior changes in this version.

## v3.5.2-industrial-tb - 2026-05-18

- Strengthened all three active testbenches with industrial-style English
  headers, interface assumptions, scoreboard notes, modeling assumptions, and
  maintenance comments.
- Added `default_nettype none` hygiene to the active testbenches.
- Added `docs/TB_INDUSTRIAL_VERIFICATION_GUIDE.md` to document TB coverage,
  pass/fail policy, and future maintenance rules.
- Synced the updated TBs and guide into the delivery package and reran the full
  Vivado XSIM regression.

## v3.5.1-cn-report - 2026-05-18

- Added a detailed Chinese final reproduction and verification report.
- Added repo-local XSIM runner scripts for one-command simulation regression.
- Converted the active legacy XDC comments to English to keep code-side
  comments English-first.
- Updated reproduction results to the latest Monte Carlo residual values.
- Refreshed the delivery package docs/scripts/checksum list.

## v3.5.0-delivery - 2026-05-18

- Standardized all active testbenches with explicit PASS/FAIL checks, sectioned
  transcripts, and fatal exits for failed batch runs.
- Added reproducible Vivado synthesis scripts under `scripts/`.
- Ran Vivado 2018.3 XSIM for all three active testbenches.
- Ran standalone synthesis checks for all three active RTL tops on
  `xc7a35tfgg484-2`.
- Added FPGA/ASIC signoff review and documented remaining integration/tapeout
  risks.
- Added a frozen delivery package under `delivery/`.

## v3.4.0-reproduction - 2026-05-18

- Added `srm_residue_estimator.sv` to reproduce the digital SRM count-to-residue boundary.
- Added `tb_srm_residue_estimator.sv`.
- Added `srm_residue` correction input to `sar_reconstruction.sv`.
- Extended `tb_sar_recon.sv` with SRM residue injection verification.
- Installed and validated the local Codex Skill `vivado-xsim`.
- Ran Vivado 2018.3 XSIM for reconstruction, calibration, and SRM estimator testbenches.
- Added a full reproduction report under `docs/`.
- Strengthened RTL/TB comments and report traceability for industrial maintenance and academic review.

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
