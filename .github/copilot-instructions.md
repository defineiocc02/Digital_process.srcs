## Purpose

Help AI coding agents understand and work efficiently in this SAR ADC digital
processing project (RTL changes, testbench updates, simulation debugging,
constraint modifications).

## Architecture (v3.6.0 Engineering Closure Baseline)

| Layer | Location | Contents |
|-------|----------|----------|
| Canonical RTL | `rtl/` | 5 SV files: 3 core + 2 tops |
| Active Vivado project | `Digital_process/` | `.xpr`, sources, sim, constraints |
| Testbench | `Digital_process/Digital_process.srcs/sim_1/new/` | 4 TB files |
| Constraints | `constraints/` | core_synth / legacy_board_hint / debug_ila_template |
| Contracts | `docs/` | FIXED_POINT_CONTRACT, MIXED_SIGNAL_TIMING_CONTRACT |
| Delivery | `delivery/sar_adc_v3_digital_core_2026-05-18/` | Frozen handoff package |
| Archive | `archive/` | Pruned files (MATLAB, legacy projects, old wrappers) |

## Module Boundaries

| Module | File | Role |
|--------|------|------|
| `sar_calib_ctrl_serial` | `rtl/sar_calib_ctrl_serial.sv` | Foreground recursive capacitor-weight calibration FSM |
| `sar_reconstruction` | `rtl/sar_reconstruction.sv` | Two-stage weighted digital reconstruction datapath |
| `srm_residue_estimator` | `rtl/srm_residue_estimator.sv` | SRM residue LUT estimator (22-decision) |
| `sar_calib_fpga_top` | `rtl/sar_calib_fpga_top.sv` | FPGA-only demo wrapper (buttons, LEDs, debug taps) |
| `sar_adc_digital_top` | `rtl/sar_adc_digital_top.sv` | ASIC digital integration skeleton |

## Authoritative Build Entry

Do **not** rely on `.xpr` top settings. Use the build scripts:

```powershell
.\scripts\build.ps1 -Target build_calib_core
.\scripts\build.ps1 -Target build_recon_core
.\scripts\build.ps1 -Target build_fpga_demo
.\scripts\build.ps1 -Target build_asic_skeleton
```

## Testbench

| TB | Target | Contract |
|----|--------|----------|
| `tb_sar_recon_binary_norm.sv` | `sar_reconstruction` | Binary-normalized 20→16 bit smoke test |
| `tb_recon_q8_split_weights.sv` | `sar_reconstruction` + `srm_residue_estimator` | Q8 split-cap bit-exact model |
| `tb_gain_comp_check_lsb.sv` | `sar_calib_ctrl_serial` | Monte Carlo gain-comp LSB check |
| `tb_srm_residue_estimator.sv` | `srm_residue_estimator` | LUT symmetry and edge cases |

Run locally:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run_all_xsim.ps1
```

## Key Design Constraints

- `CAP_NUM = 20`, `OUTPUT_WIDTH = 16`, `FRAC_BITS = 8` — parameter guards enforce these in RTL.
- `comp_out` is a **timed mixed-signal input**, not an async GPIO (see `MIXED_SIGNAL_TIMING_CONTRACT.md`).
- Weight write-back bus (`w_wr_*`) is synchronous internal — no CDC inside the core.
- FPGA top and ASIC top are intentionally separate: different ports, constraints, debug strategy.

## Pre-Commit Checks

1. All four build targets pass: `build_calib_core`, `build_recon_core`, `build_fpga_demo`, `build_asic_skeleton`.
2. `python3 scripts/check_repo_consistency.py` passes.
3. If RTL interfaces change, sync testbench instantiation and `rtl/` ↔ `Digital_process/` ↔ `delivery/`.
4. Simulation-only files must not enter the synthesis path.

## When Uncertain

- Prefer small, revertible commits.
- Update the relevant testbench and re-run XSIM before committing RTL changes.
- Parameter guards use `initial $error` — synthesis will catch illegal configurations.
- Contract documents (`FIXED_POINT_CONTRACT.md`, `MIXED_SIGNAL_TIMING_CONTRACT.md`) are authoritative for arithmetic and timing assumptions.
