# Changelog

## v3.11.0-physical-cdac-revalidation - 2026-07-29

- Rebuilt the physical-CDAC experiment with four independent ideal baselines:
  direct 16-bit quantization, no SRM, exact physical residue, and deterministic
  or stochastic 22-decision SRM.
- Explicitly disabled all ordinary normal-conversion noise while retaining the
  current stochastic SRM, proving that the no-SRM drop is uncorrected residue
  rather than hidden sampling/comparator noise.
- Completed 512/512 physical chips, full-scale and -1.72 dBFS FFT captures,
  full 16-bit static ramps, seven mismatch points, and five amplitude points.
- Added an analysis-only one-sided headroom guard. It raises the full-scale
  worst case from 55.619 dB to 93.129 dB and achieves 512/512 above 90 dB
  without the new amplification tail caused by symmetric normalization.
- Added 11 passing Python regressions, byte-identical deterministic replays,
  and a fresh Vivado 2018.3 four-testbench XSIM PASS.
- Published a 27-page detailed Chinese report with paper equations, RTL/Python
  mapping, experiment and file-operation audit, FPGA/ASIC risks, release/style
  gates, CJK ToUnicode maps, full-page visual QA, and deterministic rebuild.
- Archived the superseded v1 report and v2 symmetric-normalization outputs
  instead of deleting them.

## v3.10.0-physical-cdac-mismatch-validation - 2026-07-29

- Withdrew and archived the unsupported direct 3% effective-weight stress test.
- Added a physical 6+4+5+5 segmented-CDAC solver based on the archived project
  MATLAB topology, with unit-cap area-law mismatch, bridge mismatch, node
  parasitic variation, and comparator-input-capacitance variation.
- Added an automatic ideal 16-bit acceptance gate: 98.079 dB for the direct
  quantizer and 98.045 dB for nominal segmented CDAC plus expected-count SRM.
- Corrected dynamic SRM validation to use the paper-faithful 22 stochastic
  comparisons; the current RTL profile measures approximately 97.15 dB in the
  otherwise noiseless ideal path.
- Completed 512 physical chips at the project-MATLAB 1.2% unit-cap center and
  a six-point 0.5%-3.0% sensitivity sweep with 128 chips per point.
- Added an analysis-only finite-sample SRM study. A posterior 22-count LUT
  improves the ideal path to about 97.40 dB; a 128-count precision profile
  reaches about 97.93 dB but is not promoted into core RTL.
- Documented the remaining full-scale gain/saturation tail and preserved all
  prior artifacts under a recoverable assumption-stress-test archive.

## v3.9.2-main-unified-skill-refresh - 2026-07-29

- Synchronized `academic_report_style.tex` with the latest
  `build-academic-technical-pdf` Skill asset, SHA-256
  `64E08B6C433CEE4EA480A7DC49B260939DB53D26A7E0F05C8E4AE43325082239`.
- Updated all semantic block titles to use the same pale background as their
  bodies and removed title separator rules.
- Rebuilt the 32-page report twice with a fixed `SOURCE_DATE_EPOCH`; both
  builds produced SHA-256
  `9F4B01E4E69AB5FE2E1230CCB57DEBF63A07ECB83540F1954D86A910D1E8D731`.
- Re-ran Unicode-map injection, PDF release/style gates, full 32-page visual
  QA, delivery-local compilation, Python tests, and package integrity checks.
- Archived the preceding 32-page report and style under
  `archive/report_versions/20260729_full_sar_behavioral_v2_before_skill_refresh/`.
- Fast-forwarded the completed calibration/report history into the canonical
  `main` branch and retired the merged topic branch after remote verification.

## v3.9.1-detailed-behavioral-report - 2026-07-29

- Rewrote the full-SAR behavioral report as a 32-page chapter-based Chinese
  academic and industrial-maintenance document.
- Added detailed fixed-point, P/N calibration, recursive error, top-bit
  protection, SRM inverse-normal, Q8 reconstruction, FFT, DNL, and INL
  derivations.
- Added a complete file-operation audit, RTL-to-Python mapping, experiment
  protocol, causal decoder ablation, tail analysis, reproducibility commands,
  evidence boundaries, appendices, glossary, and references.
- Applied the current XeLaTeX academic style contract with FandolSong Chinese,
  Latin Modern text, Computer Modern math, 11 pt A4 layout, full-page visual
  QA, release-gate checks, and explicit CJK ToUnicode maps.
- Archived the replaced 9-page report under
  `archive/report_versions/20260729_full_sar_behavioral_v1_simple/`.
- Added `docs/GIT_WORKTREE_AND_BRANCH_AUDIT_2026-07-29.md`, pruned stale
  worktree registrations, and moved an unregistered Codex temporary directory
  to a recoverable archive.

## v3.9.0-full-sar-behavioral - 2026-07-29

- Added `analysis/full_sar_behavioral_20260729/` as an independent full-system
  behavioral verification area.
- Implemented a 20-decision signed differential SAR loop with effective CDAC
  mismatch, sampling/comparator noise, the current RTL P/N recursive foreground
  calibration, 22-decision SRM LUT correction, Q8 reconstruction, rounding,
  and signed 16-bit saturation.
- Completed a deterministic, restartable 512-chip campaign with four decoder
  paths and 2048 per-chip decoder records.
- Added standardized FFT metrics through the MIT-licensed ADCToolbox backend,
  plus full-range ramp-histogram DNL/INL/missing-code analysis and 8-samples-per-
  code best/median/worst tail reruns.
- Recorded calibrated+SRM medians of 91.018 dB SNDR, 108.776 dBc SFDR,
  2.015 LSB peak-to-peak INL, 1.477 LSB peak-to-peak DNL, and zero missing
  codes; retained the observed 18-code worst tail instead of treating the
  median as signoff.
- Added five Python tests, reproducibility metadata, generated CSV/JSON/NPZ
  evidence, Type-42 publication figures, and a release-checked Chinese PDF.
- Added `delivery/full_sar_behavioral_validation_20260729/` and updated the
  repository MOC, verification record, version metadata, and top-level README.

## v3.8.0-current-calibration-validation - 2026-07-29

- Added `analysis/calibration_effectiveness_20260729/` as an independent
  behavior-level verification area for the current project calibration scheme.
- Implemented `validate_current_calibration.py`, a Python model that mirrors
  the current `sar_calib_ctrl_serial.sv` P/N recursive foreground calibration
  and evaluates same-decision reconstruction paths.
- Added generated behavior evidence showing SNDR median improvement from
  36.214 dB to 92.007 dB on the diagnostic gain-aligned path, with
  gain-aligned weight RMSE reduced from 147.9781 LSB to 0.1908 LSB.
- Regenerated and checked the Chinese academic PDF validation report under
  `analysis/calibration_effectiveness_20260729/report/`.
- Reran Vivado 2018.3 XSIM full regression; all four testbenches passed.
- Added `delivery/current_calibration_validation_20260729/` with behavior
  code, current RTL/TB snapshots, report source/PDF, QA summaries, and hashes.
- Updated README/MOC/version metadata to make the current RTL, not open-source
  code, the calibration source of truth.

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
