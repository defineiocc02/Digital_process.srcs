# Project Organization

## Keep

- Three RTL files:
  - `sar_reconstruction.sv`
  - `sar_calib_ctrl_serial.sv`
  - `srm_residue_estimator.sv`
- Three testbench files:
  - `tb_sar_recon.sv`
  - `tb_gain_comp_check_lsb.sv`
  - `tb_srm_residue_estimator.sv`
- Vivado project and one XDC.
- Concise docs under `docs/`.
- Reproducible batch scripts under `scripts/`.
- Frozen delivery handoff under `delivery/`.

## Remove From Mainline

- System integration wrapper.
- SAR controller.
- Flash decoder.
- Virtual PHY model.
- System-level testbench.
- MATLAB scripts, old docs, backup copies, generated outputs.

## Archive Policy

Do not keep duplicated files in the active Vivado project. Move removed files to
tracked archive directories:

- `archive/deleted-in-039c478/`: files removed by the first prune.
- `archive/deleted-in-110ef75/`: files removed by the minimal-core prune.

The `delivery/` directory is an explicit release artifact. It may duplicate the
active core RTL/TB files intentionally so a reviewed code package can be handed
off without chasing Vivado project state.

Git history still provides recovery points:

- `archive/full-project-before-core-prune`
- commit `039c478` for the previous core source set.
