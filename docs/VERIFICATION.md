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
