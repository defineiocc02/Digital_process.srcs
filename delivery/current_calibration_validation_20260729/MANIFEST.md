# Manifest

## Behavior Model

- `behavior/validate_current_calibration.py`
- `behavior/generate_report_assets.py`
- `behavior/README.md`
- `behavior/outputs/summary.json`
- `behavior/outputs/per_chip_results.csv`
- `behavior/outputs/fig_dynamic_sndr_median.png`
- `behavior/outputs/fig_weight_rmse.png`

## RTL Source Snapshot

- `rtl/sar_calib_ctrl_serial.sv`
- `rtl/sar_reconstruction.sv`
- `rtl/srm_residue_estimator.sv`

## Testbench Snapshot

- `tb/tb_gain_comp_check_lsb.sv`
- `tb/tb_recon_q8_split_weights.sv`
- `tb/tb_sar_recon_binary_norm.sv`
- `tb/tb_srm_residue_estimator.sv`

## Documentation

- `docs/current_calibration_validation_report_cn.pdf`
- `docs/current_calibration_validation_report_cn.tex`
- `docs/generated_metrics.tex`
- `docs/summary_table.tex`
- `docs/FIXED_POINT_CONTRACT.md`

## Logs and QA

- `logs/RTL_XSIM_SUMMARY.md`
- `logs/PDF_QA_SUMMARY.md`
- `SHA256SUMS.txt`
