# MOC

## Core RTL

- `Digital_process/Digital_process.srcs/sources_1/new/sar_reconstruction.sv`
- `Digital_process/Digital_process.srcs/sources_1/new/sar_calib_ctrl_serial.sv`
- `Digital_process/Digital_process.srcs/sources_1/new/srm_residue_estimator.sv`
- `Digital_process/Digital_process.srcs/sources_1/new/sar_calib_fpga_top.sv`
- `Digital_process/Digital_process.srcs/sources_1/new/sar_adc_digital_top.sv`

## Testbench

- `Digital_process/Digital_process.srcs/sim_1/new/tb_sar_recon_binary_norm.sv` — binary-normalized 20-bit raw-code → signed 16-bit reconstruction smoke test
- `Digital_process/Digital_process.srcs/sim_1/new/tb_recon_q8_split_weights.sv` — Q8 split-cap weight consistency with bit-exact manual model
- `Digital_process/Digital_process.srcs/sim_1/new/tb_gain_comp_check_lsb.sv`
- `Digital_process/Digital_process.srcs/sim_1/new/tb_srm_residue_estimator.sv`

## Project

- `Digital_process/Digital_process.xpr`
- `Digital_process/Digital_process.srcs/constrs_1/new/sar_calib_fpga.xdc`

## Docs

- [docs/VERSION.md](docs/VERSION.md)
- [docs/FIXED_POINT_CONTRACT.md](docs/FIXED_POINT_CONTRACT.md)
- [docs/CHANGELOG.md](docs/CHANGELOG.md)
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- [docs/VERIFICATION.md](docs/VERIFICATION.md)
- [docs/TB_INDUSTRIAL_VERIFICATION_GUIDE.md](docs/TB_INDUSTRIAL_VERIFICATION_GUIDE.md)
- [docs/PROJECT_ORGANIZATION.md](docs/PROJECT_ORGANIZATION.md)
- [docs/REPRODUCTION_REPORT_2026-05-18.md](docs/REPRODUCTION_REPORT_2026-05-18.md)
- [docs/FINAL_REPRODUCTION_AND_VERIFICATION_REPORT_CN_2026-05-18.md](docs/FINAL_REPRODUCTION_AND_VERIFICATION_REPORT_CN_2026-05-18.md)
- [docs/TECHNICAL_ALGORITHM_GAP_ANALYSIS_CN_2026-05-18.md](docs/TECHNICAL_ALGORITHM_GAP_ANALYSIS_CN_2026-05-18.md)
- [docs/FPGA_ASIC_SIGNOFF_REVIEW_2026-05-18.md](docs/FPGA_ASIC_SIGNOFF_REVIEW_2026-05-18.md)

## Timing / Integration Contracts

- [docs/MIXED_SIGNAL_TIMING_CONTRACT.md](docs/MIXED_SIGNAL_TIMING_CONTRACT.md) — Mixed-signal timing contract for comparator output, SRM decision capture, reconstruction data validity, reset behavior, and FPGA/ASIC top-level separation.

## Scripts

- `scripts/run_core_synth_checks.ps1`
- `scripts/build.ps1`
- `scripts/build_vivado.tcl`
- `scripts/run_all_xsim.ps1`
- `scripts/run_xsim.ps1`
- `scripts/synth_one_top.tcl`
- `scripts/check_repo_consistency.py`
- `scripts/lint_verilator.ps1`
- `scripts/lint_verilator.sh`

## Delivery

- `delivery/sar_adc_v3_digital_core_2026-05-18/`: frozen RTL/TB/docs/scripts handoff package.

## Archive

- [archive/README.md](archive/README.md)
- `archive/deleted-in-039c478/`: first prune archive, including MATLAB and legacy projects.
- `archive/deleted-in-110ef75/`: minimal-core prune archive, including old top/control/decoder files.
- Git tag: `archive/full-project-before-core-prune`
- Previous core commit: `039c478`
