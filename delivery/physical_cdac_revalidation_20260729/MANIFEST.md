# Manifest

## RTL Truth Snapshot

- `rtl/sar_calib_ctrl_serial.sv`
- `rtl/sar_reconstruction.sv`
- `rtl/srm_residue_estimator.sv`

## Industrial Testbenches

- `tb/tb_sar_recon_binary_norm.sv`
- `tb/tb_recon_q8_split_weights.sv`
- `tb/tb_srm_residue_estimator.sv`
- `tb/tb_gain_comp_check_lsb.sv`

## Revalidation Model

- `analysis/physical_cdac_mismatch_20260729/physical_cdac.py`
- `analysis/physical_cdac_mismatch_20260729/run_physical_mismatch.py`
- `analysis/physical_cdac_mismatch_20260729/run_revalidation.py`
- `analysis/physical_cdac_mismatch_20260729/revalidation_spec.yml`
- `analysis/physical_cdac_mismatch_20260729/test_physical_cdac.py`
- `analysis/physical_cdac_mismatch_20260729/test_revalidation.py`
- `analysis/full_sar_behavioral_20260729/full_sar_model.py`
- `analysis/full_sar_behavioral_20260729/requirements.txt`
- `analysis/full_sar_behavioral_20260729/THIRD_PARTY_NOTICES.md`

## Formal Evidence

- `evidence/summary.json`
- `evidence/per_chip_main_metrics.csv`
- `evidence/per_chip_physical_metrics.csv`
- `evidence/per_chip_sigma_metrics.csv`
- `evidence/sigma_summary.csv`
- `evidence/per_chip_amplitude_metrics.csv`
- `evidence/amplitude_summary.csv`
- `evidence/fig_revalidation_main.{png,pdf}`
- `evidence/fig_revalidation_static.{png,pdf}`
- `evidence/fig_revalidation_sigma_sweep.{png,pdf}`
- `evidence/fig_revalidation_amplitude_sweep.{png,pdf}`

## Report And Maintenance Documents

- `report/physical_cdac_revalidation_cn.pdf`
- `report/physical_cdac_revalidation_cn.tex`
- `report/academic_report_style.tex`
- `report/generate_report_assets.py`
- `docs/README.md`
- `docs/VALIDATION_REPORT_CN.md`
- `docs/RUN_LOG.md`
- `docs/FIXED_POINT_CONTRACT.md`
- `docs/MIXED_SIGNAL_TIMING_CONTRACT.md`
- `docs/VERIFICATION.md`
- `docs/VERSION.md`
- `docs/CHANGELOG.md`

`SHA256SUMS.txt` is generated after package assembly and covers every release
file except itself. Runtime caches and `sim_work/` are excluded.
