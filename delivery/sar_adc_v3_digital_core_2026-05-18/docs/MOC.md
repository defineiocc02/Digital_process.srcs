# MOC

## Core RTL

- `Digital_process/Digital_process.srcs/sources_1/new/sar_reconstruction.sv`
- `Digital_process/Digital_process.srcs/sources_1/new/sar_calib_ctrl_serial.sv`
- `Digital_process/Digital_process.srcs/sources_1/new/srm_residue_estimator.sv`

## Testbench

- `Digital_process/Digital_process.srcs/sim_1/new/tb_sar_recon.sv`
- `Digital_process/Digital_process.srcs/sim_1/new/tb_gain_comp_check_lsb.sv`
- `Digital_process/Digital_process.srcs/sim_1/new/tb_srm_residue_estimator.sv`

## Project

- `Digital_process/Digital_process.xpr`
- `Digital_process/Digital_process.srcs/constrs_1/new/sar_calib_fpga.xdc`

## Docs

- [docs/VERSION.md](docs/VERSION.md)
- [docs/CHANGELOG.md](docs/CHANGELOG.md)
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- [docs/VERIFICATION.md](docs/VERIFICATION.md)
- [docs/PROJECT_ORGANIZATION.md](docs/PROJECT_ORGANIZATION.md)
- [docs/REPRODUCTION_REPORT_2026-05-18.md](docs/REPRODUCTION_REPORT_2026-05-18.md)
- [docs/FPGA_ASIC_SIGNOFF_REVIEW_2026-05-18.md](docs/FPGA_ASIC_SIGNOFF_REVIEW_2026-05-18.md)

## Scripts

- `scripts/run_core_synth_checks.ps1`
- `scripts/synth_one_top.tcl`

## Delivery

- `delivery/sar_adc_v3_digital_core_2026-05-18/`: frozen RTL/TB/docs/scripts handoff package.

## Archive

- [archive/README.md](archive/README.md)
- `archive/deleted-in-039c478/`: first prune archive, including MATLAB and legacy projects.
- `archive/deleted-in-110ef75/`: minimal-core prune archive, including old top/control/decoder files.
- Git tag: `archive/full-project-before-core-prune`
- Previous core commit: `039c478`
