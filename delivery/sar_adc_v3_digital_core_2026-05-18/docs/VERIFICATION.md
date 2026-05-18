# Verification

## Testbenches

| Testbench | Target | Purpose |
| --- | --- | --- |
| `tb_sar_recon.sv` | `sar_reconstruction` | Weighted reconstruction, weight update response, pipeline throughput, SRM residue injection |
| `tb_gain_comp_check_lsb.sv` | `sar_calib_ctrl_serial` | Monte Carlo foreground calibration with offset/noise and gain compensation |
| `tb_srm_residue_estimator.sv` | `srm_residue_estimator` | 22-decision SRM counter and LUT behavior |

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

## Latest Run

Date: 2026-05-18

- `tb_sar_recon`: PASS, 48 checks, 0 failed; includes ideal linearity,
  calibration weight write sensitivity, full-rate pipeline throughput, and SRM
  residue injection.
- `tb_srm_residue_estimator`: PASS, 17 checks, 0 failed; includes edge,
  midpoint, and symmetry LUT cases.
- `tb_gain_comp_check_lsb`: PASS, 5 Monte Carlo runs, 10 checks, 0 failed;
  worst residual error `0.4937 LSB`.

Synthesis check:

- `scripts/run_core_synth_checks.ps1`: PASS for `sar_reconstruction`,
  `srm_residue_estimator`, and `sar_calib_ctrl_serial` on `xc7a35tfgg484-2`
  with a 100 MHz clock.
- Post-synthesis worst setup slack: `3.999 ns`, `7.480 ns`, and `5.450 ns`
  respectively.

Known warnings and limits:

- Vivado reports a local Tcl store permission warning on this Windows machine;
  this is an environment warning, not an RTL warning.
- Standalone synthesis does not replace final FPGA/ASIC signoff. See
  `docs/FPGA_ASIC_SIGNOFF_REVIEW_2026-05-18.md`.
- Detailed Chinese execution and algorithm report:
  `docs/FINAL_REPRODUCTION_AND_VERIFICATION_REPORT_CN_2026-05-18.md`.

## Maintenance Rule

For any future RTL behavior change, rerun all three testbenches and update the
latest-run section with the new date, simulator version, pass/fail status, and
worst calibration residual.
