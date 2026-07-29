# Revalidation Run Log

Date: 2026-07-29
Workspace: `D:\ReedZhao\Document\ADC_Digital_PROCESS\proc_vivado\sar_adc_v3`

## Python Regression

```powershell
python -m pytest `
  analysis\physical_cdac_mismatch_20260729\test_physical_cdac.py `
  analysis\physical_cdac_mismatch_20260729\test_revalidation.py -q
```

Result: `11 passed in 3.42s`.

## Formal Campaign

```powershell
python analysis\physical_cdac_mismatch_20260729\run_revalidation.py `
  --chips 512 --sensitivity-chips 128 --amplitude-chips 128 --workers 6
```

Result:

- Main: `512/512` completed.
- Sigma sweep: `896/896` completed.
- Amplitude sweep: `128/128` completed.
- stderr: empty.
- Experiment version: `3.0`.

## Deterministic Replay

Two independent runs used `8` main chips, `8` chips/sigma point, and `8`
amplitude chips. The following artifacts matched byte-for-byte:

- `per_chip_main_metrics.csv`
- `per_chip_physical_metrics.csv`
- `per_chip_sigma_metrics.csv`
- `sigma_summary.csv`
- `per_chip_amplitude_metrics.csv`
- `amplitude_summary.csv`
- `summary.json`

The first 8 formal main-chip records also matched the replay row-for-row.

## Vivado 2018.3 XSIM

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_all_xsim.ps1
```

Result: `XSIM OVERALL RESULT : PASS`.

| Testbench | Result |
| --- | --- |
| `tb_sar_recon_binary_norm` | 49 checks, 0 failed |
| `tb_recon_q8_split_weights` | 17 checks, 0 failed |
| `tb_srm_residue_estimator` | 17 checks, 0 failed |
| `tb_gain_comp_check_lsb` | 5 MC passed, worst 0.4937 LSB |

## PDF Build And QA

- XeLaTeX: 3 passes with fixed `SOURCE_DATE_EPOCH`.
- CJK ToUnicode injection: PASS, 2 fonts and 869 codes mapped.
- Release gate: PASS, 27 A4 pages, no Type 3 or unembedded fonts.
- Reference style gate: PASS.
- Visual QA: all 27 pages rendered and inspected.
- Deterministic rebuild: PASS.
- Final report SHA-256:
  `96F3C087A7561579FB1D7DB9870A4C155F12872155EE64F6851B2343719A3189`.

## Frozen Delivery Package Audit

The package at `delivery/physical_cdac_revalidation_20260729/` was tested from
its own root after assembly.

- Python regression: `11 passed in 3.36s`.
- Vivado source layout: `delivery package`.
- All four XSIM testbenches compiled, elaborated, and passed.
- Package checksum verification covers 57 release files.
- The packaged report SHA-256 is identical to the formal source report.
