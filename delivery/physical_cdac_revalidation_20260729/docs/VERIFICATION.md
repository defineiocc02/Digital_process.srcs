# Verification

## Testbenches

| Testbench | Target | Purpose |
| --- | --- | --- |
| `tb_sar_recon_binary_norm.sv` | `sar_reconstruction` | Binary-normalized 20-bit raw-code to signed 16-bit reconstruction smoke test |
| `tb_recon_q8_split_weights.sv` | `sar_reconstruction` | Q8 split-cap weight, SRM residue, and reconstruction fixed-point contract |
| `tb_gain_comp_check_lsb.sv` | `sar_calib_ctrl_serial` | Monte Carlo foreground calibration with offset/noise and gain compensation |
| `tb_srm_residue_estimator.sv` | `srm_residue_estimator` | 22-decision SRM counter and LUT behavior |

Industrial TB maintenance guide:

```text
docs/TB_INDUSTRIAL_VERIFICATION_GUIDE.md
```

All active TBs use English-first comments, centralized `record_check`
scoreboards, `$fatal` on failure, transcript-level PASS/FAIL summaries, and
`default_nettype none` to catch accidental implicit nets.

## Vivado XSIM

Vivado 2018.3 command-line simulation is available through:

```text
D:\Academic\Vivado2018\Vivado\2018.3\bin\xvlog.bat
D:\Academic\Vivado2018\Vivado\2018.3\bin\xelab.bat
D:\Academic\Vivado2018\Vivado\2018.3\bin\xsim.bat
```

The reusable Codex Skill is installed at:

```text
C:\Users\Administrator\.codex\skills\vivado-xsim
```

Repository-local regression command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run_all_xsim.ps1
```

Delivery-package regression command:

```powershell
cd delivery\sar_adc_v3_digital_core_2026-05-18
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run_all_xsim.ps1
```

## Latest Run

Date: 2026-07-29

Physical-CDAC mismatch revalidation:

- Formal runner: `analysis/physical_cdac_mismatch_20260729/run_revalidation.py`.
- Physical center: 6+4+5+5 segmented CDAC, 8 fF unit capacitor, 1.2% unit-cap
  RMS mismatch with area-law scaling, and 2% parasitic/input-cap variation.
- Ordinary sampling, normal-comparator, reference, and settling noise are all
  disabled; dynamic captures retain the current stochastic 22-decision SRM.
- Ideal direct quantizer / exact residue / expected SRM / stochastic SRM SNDR:
  `98.079 / 98.079 / 98.045 / 97.145 dB`.
- Formal main campaign: `512/512` physical chips and 3072 decoder rows.
- Current calibration full-scale median/minimum: `95.256 / 55.619 dB`; backed-
  off median/minimum: `93.577 / 91.206 dB`.
- Current static DNL max, INL max, and missing-code medians:
  `0.968 LSB / 0.993 LSB / 0`; worst missing-code count remains `30`.
- Analysis-only one-sided headroom guard: full-scale minimum `93.129 dB`,
  `512/512` above 90 dB. It is not current RTL.
- Python regression: `11 passed`; deterministic 8-chip dual replay matched
  seven CSV/JSON artifacts byte-for-byte and matched the formal first 8 chips.
- Detailed 27-page report SHA-256:
  `96F3C087A7561579FB1D7DB9870A4C155F12872155EE64F6851B2343719A3189`.
- Report release, reference-style, CJK ToUnicode, full-page visual, and
  deterministic rebuild gates: PASS.

- `tb_sar_recon_binary_norm`: PASS after the fixed-point contract split;
  49 checks, 0 failed; includes ideal binary-normalized linearity, weight
  write sensitivity, full-rate pipeline throughput, and SRM residue injection.
- `tb_recon_q8_split_weights`: PASS after introduction; checks Q8 split-cap
  ideal weights, non-saturated residue unit behavior, and bit-exact agreement
  with the manual reconstruction model; 17 checks, 0 failed.
- `tb_srm_residue_estimator`: PASS, 17 checks, 0 failed; includes edge,
  midpoint, and symmetry LUT cases.
- `tb_gain_comp_check_lsb`: PASS, 5 Monte Carlo runs, 10 checks, 0 failed;
  worst residual error `0.4937 LSB`.
- Active source tree was rerun through `scripts/run_all_xsim.ps1` on
  2026-07-29 and ended with `XSIM OVERALL RESULT : PASS`.

Current on-chip calibration behavior-level validation:

- Algorithm source of truth: `rtl/sar_calib_ctrl_serial.sv`.
- Behavior mirror and evidence:
  `analysis/calibration_effectiveness_20260729/validate_current_calibration.py`.
- Result summary under the configured 32-chip stress case:
  nominal SNDR median `36.214 dB`; RTL-equivalent calibrated raw path
  `91.967 dB`; diagnostic gain-aligned calibrated path `92.007 dB`;
  physical-weight oracle `93.292 dB`.
- Gain-aligned weight RMSE median improved from `147.9781 LSB` to
  `0.1908 LSB`.
- Report and package:
  `analysis/calibration_effectiveness_20260729/report/current_calibration_validation_report_cn.pdf`
  and `delivery/current_calibration_validation_20260729/`.
- This validation does not claim AMS, transistor-level, PVT, PEX, or silicon
  signoff.

Full SAR behavior-level validation:

- Model and runner:
  `analysis/full_sar_behavioral_20260729/full_sar_model.py` and
  `analysis/full_sar_behavioral_20260729/run_campaign.py`.
- Algorithm source of truth remains the local RTL:
  `rtl/sar_calib_ctrl_serial.sv`, `rtl/srm_residue_estimator.sv`, and
  `rtl/sar_reconstruction.sv`.
- Formal campaign completed `512/512` independent virtual chips and emitted
  `2048` decoder rows for nominal/no-SRM, calibrated/no-SRM, calibrated/SRM,
  and physical-weight-oracle/SRM paths.
- Calibrated/SRM dynamic result: SNDR P01/median/P99 =
  `89.680 / 91.018 / 91.533 dB`; SFDR median = `108.776 dBc`.
- Calibrated/SRM static result: INL peak-to-peak median/P95 =
  `2.015 / 2.774 LSB`; DNL peak-to-peak median/P95 =
  `1.477 / 1.970 LSB`; missing-code median/P95/max = `0 / 4 / 18`.
- Best/median/worst representative chips were rerun at eight ramp samples per
  code. The worst representative retained `2` missing codes with
  `2.796 LSB` INL peak-to-peak.
- Python regression: `5 passed`.
- Latest-Skill detailed report release gate: PASS, 32 pages, SHA-256
  `9F4B01E4E69AB5FE2E1230CCB57DEBF63A07ECB83540F1954D86A910D1E8D731`.
- The report passed `check_pdf_release.py`, `check_reference_style.py`, CJK
  ToUnicode injection, font embedding inspection, and full 32-page visual QA.
- Two complete three-pass XeLaTeX release builds with fixed
  `SOURCE_DATE_EPOCH` produced the same PDF SHA-256.
- The synchronized Skill style asset SHA-256 is
  `64E08B6C433CEE4EA480A7DC49B260939DB53D26A7E0F05C8E4AE43325082239`.
- ADCToolbox 0.9.1, commit
  `a8995cf4faf73dde9918589bfeb866c6a77db12d`, is used only for standardized
  spectrum and ramp-histogram metrics under its MIT license.
- This is behavior-level L2 evidence. It does not claim charge-domain CDAC
  equivalence, AMS/PVT/PEX closure, FPGA timing closure, or silicon yield.

Python convergence-analysis run:

- `python -B analysis\surrogate\replicate_huang2025_calibration_convergence.py`:
  PASS, deterministic 80-chip paired Monte Carlo sweep with an explicit
  quantized 16-bit output boundary.
- Proxy qualification reports direct RTL-Q8 mapping saturation of `23.9151%`;
  the proxy therefore remains trend-only and is not an RTL/analog golden
  closed loop.
- Descriptive trend markers are first met at `Navg=32` with SS+SRM and
  `Navg=256` without SS+SRM, a model-reported `8.0x` ratio.
- Full interpretation and limits are documented in
  `docs/HUANG2025_SURROGATE_MODEL_REVIEW_CN_2026-05-26.md`.

Synthesis check:

- `scripts/build.ps1`: PASS for `build_calib_core`, `build_recon_core`,
  `build_fpga_demo`, and `build_asic_skeleton` on `xc7a35tfgg484-2` with a
  100 MHz clock.
- Post-synthesis worst setup slack: `5.449 ns`, `3.999 ns`, `5.441 ns`,
  and `3.957 ns` respectively.
- Current post-synthesis utilization (`Slice LUTs / Slice Registers`):
  `529 / 821`, `950 / 818`, `462 / 821`, and `1518 / 1661` respectively.
- Vivado emitted non-critical optimization/floorplanning advisory warnings
  for standalone/flattened synthesis; no synthesis target emitted an error or
  critical warning.

Additional package-entry check:

- `delivery/sar_adc_v3_digital_core_2026-05-18/scripts/run_all_xsim.ps1`:
  PASS, using package-local `rtl/` and `tb/` files.

## Lightweight CI

The repository includes a lightweight GitHub Actions workflow
(`.github/workflows/rtl_lint.yml`) that runs on every push and pull request:

1. `scripts/check_repo_consistency.py` — verifies that required RTL, TB,
   constraint, and contract files exist; detects stale legacy filenames;
   validates core XDC purity and build target completeness.
2. `scripts/lint_verilator.sh` — runs Verilator `--lint-only -Wall` on all
   five RTL files to catch syntax, width, and port regressions.

Vivado XSIM and synthesis remain **local** signoff steps because they require a
Vivado installation and license.

## Known warnings and limits:

- Vivado reports a local Tcl store permission warning on this Windows machine;
  this is an environment warning, not an RTL warning.
- Standalone synthesis does not replace final FPGA/ASIC signoff. See
  `docs/FPGA_ASIC_SIGNOFF_REVIEW_2026-05-18.md`.
- Detailed Chinese execution and algorithm report:
  `docs/FINAL_REPRODUCTION_AND_VERIFICATION_REPORT_CN_2026-05-18.md`.

## Maintenance Rule

For any future RTL behavior change, rerun all active testbenches and update the
latest-run section with the new date, simulator version, pass/fail status, and
worst calibration residual.
