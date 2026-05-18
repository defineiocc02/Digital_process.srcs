# Requirements

## Functional Scope

The active project reproduces the digital algorithm boundary for a split-sampling
16-bit SAR ADC:

1. Foreground recursive bit-weight self-calibration.
2. Calibrated digital reconstruction.
3. Statistical residue measurement digital estimation.

## Required RTL

- `sar_calib_ctrl_serial.sv`
- `sar_reconstruction.sv`
- `srm_residue_estimator.sv`

## Required Testbenches

- `tb_gain_comp_check_lsb.sv`
- `tb_sar_recon_binary_norm.sv`
- `tb_recon_q8_split_weights.sv`
- `tb_srm_residue_estimator.sv`

## Non-Goals

This repository does not reproduce transistor-level split-sampling, autozero,
flash pre-quantization, or analog noise circuitry. Those effects are modeled at
the testbench boundary so the digital algorithm can be verified repeatably.
