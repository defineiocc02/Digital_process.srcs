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

## Latest Run

Date: 2026-05-18

- `tb_srm_residue_estimator`: PASS.
- `tb_sar_recon`: PASS, including SRM residue injection.
- `tb_gain_comp_check_lsb`: PASS, 5 Monte Carlo runs, worst residual error `0.4532 LSB`.

Known warning:

- Vivado 2018.3 warns that `ABS_ERR_LIMIT` in the calibration TB should be
  explicitly declared `automatic` or `static`; this is a testbench style warning
  and does not change the result.
