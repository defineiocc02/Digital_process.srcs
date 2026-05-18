# SAR ADC V3 Minimal Core

This repository keeps the active Vivado project intentionally small. The main
project contains the calibration, digital reconstruction, and SRM residue
estimation blocks needed to reproduce the digital algorithm boundary. Files
removed from the active project are preserved under `archive/`.

## Version

- Version: `v3.5.4-fixed-point-contract`
- Fixed-point contract: `docs/FIXED_POINT_CONTRACT.md`
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

## Vivado Entry Points

- Project: `Digital_process/Digital_process.xpr`
- Default synthesis top: `sar_reconstruction`
- Default simulation top: `tb_sar_recon_binary_norm`
- Calibration simulation top: switch to `tb_gain_comp_check_lsb` when needed.
- Batch XSIM regression: `scripts/run_all_xsim.ps1`
- Batch synthesis check: `scripts/run_core_synth_checks.ps1`

## Vivado XSIM

The local Codex Skill `vivado-xsim` was created at:

```text
C:\Users\Administrator\.codex\skills\vivado-xsim
```

It wraps the working Vivado 2018.3 `xvlog/xelab/xsim` batch flow.

## Archive

- `archive/deleted-in-039c478/`: MATLAB scripts, legacy Vivado projects, backup RTL/TB, old docs, scripts, and reports removed by the first prune.
- `archive/deleted-in-110ef75/`: former top wrapper, SAR controller, flash decoder, virtual ADC model, and duplicate TBs removed by the minimal-core prune.

The archive is retained for recovery and comparison, but it is not part of the
active Vivado source set.
