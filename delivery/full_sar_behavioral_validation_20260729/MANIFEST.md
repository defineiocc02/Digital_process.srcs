# Manifest

## Behavior Model

- `behavior/__init__.py`
- `behavior/full_sar_model.py`
- `behavior/run_campaign.py`
- `behavior/test_full_sar_model.py`
- `behavior/spec.yml`
- `behavior/requirements.txt`
- `behavior/THIRD_PARTY_NOTICES.md`

## Formal Outputs

- `behavior/outputs/summary.json`
- `behavior/outputs/per_chip_decoder_metrics.csv`
- `behavior/outputs/fig_*.png`
- `behavior/outputs/fig_*.pdf`
- `behavior/outputs/highres_*.npz`

The 512 per-chip checkpoint JSON files are intentionally omitted. They are
restart artifacts, not the final evidence record.

## RTL And Testbench Snapshots

- `rtl/sar_calib_ctrl_serial.sv`
- `rtl/srm_residue_estimator.sv`
- `rtl/sar_reconstruction.sv`
- `tb/tb_gain_comp_check_lsb.sv`
- `tb/tb_recon_q8_split_weights.sv`
- `tb/tb_sar_recon_binary_norm.sv`
- `tb/tb_srm_residue_estimator.sv`

## Report And Contracts

- `report/full_sar_behavioral_validation_cn.pdf`
- `report/full_sar_behavioral_validation_cn.tex`
- `report/generate_report_assets.py`
- `report/generated_metrics.tex`
- `report/dynamic_table_rows.tex`
- `report/static_table_rows.tex`
- `report/representative_table_rows.tex`
- `docs/FIXED_POINT_CONTRACT.md`
- `docs/VERIFICATION.md`

## QA And Integrity

- `logs/PYTHON_CAMPAIGN_SUMMARY.md`
- `logs/PDF_QA_SUMMARY.md`
- `SHA256SUMS.txt`
