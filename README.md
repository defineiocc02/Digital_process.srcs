# SAR ADC V3 Minimal Core

This repository keeps the active Vivado project intentionally small. The main
project contains the calibration, digital reconstruction, and SRM residue
estimation blocks needed to reproduce the digital algorithm boundary. Files
removed from the active project are preserved under `archive/`.

## Version

- Version: `v3.5.4-fixed-point-contract`
- Fixed-point contract: `docs/FIXED_POINT_CONTRACT.md`
- Mixed-signal timing contract: `docs/MIXED_SIGNAL_TIMING_CONTRACT.md` — Defines timing assumptions for comparator, SRM, reconstruction inputs, reset, and FPGA/ASIC integration boundaries.
- Reproduction report: `docs/REPRODUCTION_REPORT_2026-05-18.md`
- Chinese final report: `docs/FINAL_REPRODUCTION_AND_VERIFICATION_REPORT_CN_2026-05-18.md`
- Technical gap analysis: `docs/TECHNICAL_ALGORITHM_GAP_ANALYSIS_CN_2026-05-18.md`
- TB verification guide: `docs/TB_INDUSTRIAL_VERIFICATION_GUIDE.md`
- FPGA/ASIC review: `docs/FPGA_ASIC_SIGNOFF_REVIEW_2026-05-18.md`
- Delivery package: `delivery/sar_adc_v3_digital_core_2026-05-18/`
- Full organized archive tag: `archive/full-project-before-core-prune`

## Active Project

```text
sar_adc_v3/
|-- Digital_process/
|   |-- Digital_process.xpr
|   `-- Digital_process.srcs/
|       |-- sources_1/new/
|       |   |-- sar_calib_ctrl_serial.sv
|       |   |-- sar_reconstruction.sv
|       |   `-- srm_residue_estimator.sv
|       |-- sim_1/new/
|       |   |-- tb_gain_comp_check_lsb.sv
|       |   |-- tb_recon_q8_split_weights.sv
|       |   |-- tb_sar_recon_binary_norm.sv
|       |   `-- tb_srm_residue_estimator.sv
|       `-- constrs_1/new/
|           `-- sar_calib_fpga.xdc
|-- archive/
|-- delivery/
|-- docs/
|-- scripts/
|-- MOC.md
`-- README.md
```

## Authoritative Build Targets

The Vivado `.xpr` file is **not** the authoritative build source.  
Use the batch scripts under `scripts/` to select the intended synthesis top.

| Target | Top Module | Purpose |
|---|---|---|
| `build_calib_core` | `sar_calib_ctrl_serial` | Standalone calibration controller synthesis |
| `build_recon_core` | `sar_reconstruction` | Standalone reconstruction datapath synthesis |
| `build_fpga_demo` | `sar_calib_fpga_top` | FPGA board/demo top |

```powershell
.\scripts\build.ps1 -Target build_calib_core
.\scripts\build.ps1 -Target build_recon_core
.\scripts\build.ps1 -Target build_fpga_demo
```

### Simulation & Legacy Entry Points

- Default simulation top: `tb_sar_recon_binary_norm` — verifies binary-normalized
  20-bit raw-code to signed 16-bit reconstruction only. It does **not** verify
  calibrated Q8 split-cap weight consistency; for that use
  `tb_recon_q8_split_weights`.
- Calibration simulation top: switch to `tb_gain_comp_check_lsb` when needed.
- Batch XSIM regression: `scripts/run_all_xsim.ps1`
- Legacy batch synthesis check: `scripts/run_core_synth_checks.ps1`
- Vivado GUI project (non-authoritative): `Digital_process/Digital_process.xpr`

## Vivado XSIM

The local Codex Skill `vivado-xsim` was created at:

```text
C:\Users\Administrator\.codex\skills\vivado-xsim
```

It wraps the working Vivado 2018.3 `xvlog/xelab/xsim` batch flow.

## Top-Level Strategy

This project uses separate FPGA and ASIC top-level wrappers.

| Top Module | Purpose | Notes |
|---|---|---|
| `sar_calib_fpga_top` | FPGA board/demo wrapper | May include board IO, debug taps, and FPGA-only integration |
| `sar_adc_digital_top` | ASIC-oriented digital integration skeleton | Must not include FPGA buttons, LEDs, or ILA IP |
| `sar_calib_ctrl_serial` | Calibration core standalone synthesis | Core target only |
| `sar_reconstruction` | Reconstruction core standalone synthesis | Core target only |

The FPGA top and ASIC digital top are intentionally separate because their
ports, constraints, debug strategy, and synthesis assumptions are different.

## Constraint Strategy

| XDC | Purpose | Used by default |
|---|---|---|
| `constraints/core_synth.xdc` | Minimal 100 MHz core clock constraint | Yes |
| `constraints/sar_calib_fpga_legacy_board_hint.xdc` | Historical FPGA board pin hints (ACX720-V3) | No — opt-in via `USE_BOARD_XDC=1` |
| `constraints/debug_ila_template.xdc` | ILA/debug tap template (comment-only) | No — opt-in via `USE_DEBUG_XDC=1` |

Core builds must not read board-level or debug constraints by default.

Board-level constraints are valid only when the selected FPGA wrapper exposes
matching ports. Debug constraints must be enabled only after debug taps and ILA
connectivity are deliberately reviewed.

## Lightweight CI / Lint

This repository provides a lightweight open-source CI path for repository
consistency and RTL lint.

```bash
python3 scripts/check_repo_consistency.py
bash scripts/lint_verilator.sh
```

The GitHub Actions workflow (`.github/workflows/rtl_lint.yml`) runs both on
every push and pull request.

Vivado XSIM and synthesis are still run **locally** because they require a
licensed Vivado installation:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run_all_xsim.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run_core_synth_checks.ps1
```

The CI workflow does not replace Vivado signoff. It only catches structural
regressions, missing files, stale filenames, and basic SystemVerilog lint
issues.

## Archive

- `archive/deleted-in-039c478/`: MATLAB scripts, legacy Vivado projects, backup RTL/TB, old docs, scripts, and reports removed by the first prune.
- `archive/deleted-in-110ef75/`: former top wrapper, SAR controller, flash decoder, virtual ADC model, and duplicate TBs removed by the minimal-core prune.

The archive is retained for recovery and comparison, but it is not part of the
active Vivado source set.
