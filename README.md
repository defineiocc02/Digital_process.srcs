# SAR ADC V3 Minimal Core

This repository keeps the active Vivado project intentionally small. The main
project contains only the calibration and digital reconstruction cores plus their
direct testbenches. Files removed from the active project are preserved under
`archive/`.

## Version

- Version: `v3.3.1-archive`
- Latest commit before this archive update: `110ef75`
- Full organized archive tag: `archive/full-project-before-core-prune`

## Active Project

```text
sar_adc_v3/
|-- Digital_process/
|   |-- Digital_process.xpr
|   `-- Digital_process.srcs/
|       |-- sources_1/new/
|       |   |-- sar_calib_ctrl_serial.sv
|       |   `-- sar_reconstruction.sv
|       |-- sim_1/new/
|       |   |-- tb_gain_comp_check_lsb.sv
|       |   `-- tb_sar_recon.sv
|       `-- constrs_1/new/
|           `-- sar_calib_fpga.xdc
|-- archive/
|-- docs/
|-- MOC.md
`-- README.md
```

## Vivado Entry Points

- Project: `Digital_process/Digital_process.xpr`
- Default synthesis top: `sar_reconstruction`
- Default simulation top: `tb_sar_recon`
- Calibration simulation top: switch to `tb_gain_comp_check_lsb` when needed.

## Archive

- `archive/deleted-in-039c478/`: MATLAB scripts, legacy Vivado projects, backup RTL/TB, old docs, scripts, and reports removed by the first prune.
- `archive/deleted-in-110ef75/`: former top wrapper, SAR controller, flash decoder, virtual ADC model, and duplicate TBs removed by the minimal-core prune.

The active RTL logic was not changed in the archive update.
