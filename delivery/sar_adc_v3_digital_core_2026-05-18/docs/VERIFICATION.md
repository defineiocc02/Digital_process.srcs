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

Date: 2026-05-18

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
- Active source tree and frozen delivery package were both run through
  `scripts/run_all_xsim.ps1`; both ended with `XSIM OVERALL RESULT : PASS`.

Synthesis check:

- `scripts/run_core_synth_checks.ps1`: PASS for `sar_reconstruction`,
  `srm_residue_estimator`, and `sar_calib_ctrl_serial` on `xc7a35tfgg484-2`
  with a 100 MHz clock.
- Post-synthesis worst setup slack: `3.999 ns`, `7.480 ns`, and `5.450 ns`
  respectively.

Additional package-entry check:

- `delivery/sar_adc_v3_digital_core_2026-05-18/scripts/run_all_xsim.ps1`:
  PASS, using package-local `rtl/` and `tb/` files.

Known warnings and limits:

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
