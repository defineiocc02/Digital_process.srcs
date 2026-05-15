# Project Organization

## Keep

- Two RTL files:
  - `sar_reconstruction.sv`
  - `sar_calib_ctrl_serial.sv`
- Two testbench files:
  - `tb_sar_recon.sv`
  - `tb_gain_comp_check_lsb.sv`
- Vivado project and one XDC.
- Concise docs under `docs/`.

## Remove From Mainline

- System integration wrapper.
- SAR controller.
- Flash decoder.
- Virtual PHY model.
- System-level testbench.
- MATLAB scripts, old docs, backup copies, generated outputs.

## Archive Policy

Do not keep duplicated files in the working tree. Use Git history:

- `archive/full-project-before-core-prune`
- commit `039c478` for the previous core source set.
