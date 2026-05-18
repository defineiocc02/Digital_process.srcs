# Runbook

## Environment

Known working Vivado installation:

```text
D:\Academic\Vivado2018\Vivado\2018.3\bin
```

## XSIM Examples

For TB scope, pass/fail policy, and maintenance rules, read:

```text
docs\TB_INDUSTRIAL_VERIFICATION_GUIDE.md
```

Fixed-point units are documented in:

```text
docs\FIXED_POINT_CONTRACT.md
```

From the package root, run the complete package-local regression:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run_all_xsim.ps1
```

From the package root, run one testbench at a time:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run_xsim.ps1 `
  -VivadoBin 'D:\Academic\Vivado2018\Vivado\2018.3\bin' `
  -WorkDir sim_work\tb_sar_recon_binary_norm `
  -Top tb_sar_recon_binary_norm `
  -Files @('rtl\sar_reconstruction.sv','tb\tb_sar_recon_binary_norm.sv')
```

Change `-Top` and `-Files` for:

- `tb_recon_q8_split_weights`: `rtl\sar_reconstruction.sv`, `tb\tb_recon_q8_split_weights.sv`
- `tb_srm_residue_estimator`: `rtl\srm_residue_estimator.sv`, `tb\tb_srm_residue_estimator.sv`
- `tb_gain_comp_check_lsb`: `rtl\sar_calib_ctrl_serial.sv`, `tb\tb_gain_comp_check_lsb.sv`

When working from the original repository root, run the full active regression:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run_all_xsim.ps1
```

## Synthesis Check

From the original repository root, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run_core_synth_checks.ps1
```

From the package root, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run_package_synth_checks.ps1
```
