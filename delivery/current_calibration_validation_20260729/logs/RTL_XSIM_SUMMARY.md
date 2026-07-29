# RTL XSIM Summary

Date: 2026-07-29

Command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run_all_xsim.ps1
```

Vivado simulator:

- Vivado 2018.3 XSIM
- Tool path: `D:\Academic\Vivado2018\Vivado\2018.3\bin`

Results:

| Testbench | Result | Checks |
|---|---:|---:|
| `tb_sar_recon_binary_norm` | PASS | 49 checks, 0 failed |
| `tb_recon_q8_split_weights` | PASS | 17 checks, 0 failed |
| `tb_srm_residue_estimator` | PASS | 17 checks, 0 failed |
| `tb_gain_comp_check_lsb` | PASS | 5 Monte Carlo runs, worst residual 0.4937 LSB |

Overall result: PASS.

Scope:

This proves that the current SystemVerilog RTL compiles and passes the repository unit-level reconstruction, SRM residue, Q8 split-weight contract, and calibration-controller testbenches. It does not replace mixed-signal, transistor-level, PVT, post-layout, or silicon validation.
