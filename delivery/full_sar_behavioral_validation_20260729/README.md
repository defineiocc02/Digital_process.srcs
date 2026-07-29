# Full SAR Behavioral Validation Delivery Package

Date: 2026-07-29

This package contains the independent full behavioral loop for the current
20-decision SAR ADC project. The executable path covers:

```text
sampled input
-> effective CDAC mismatch and comparator decisions
-> current-RTL P/N recursive foreground calibration
-> 22-decision SRM residue estimate
-> Q8 signed differential reconstruction
-> signed 16-bit decode
-> FFT and full-range DNL/INL analysis
```

## Source-Of-Truth Boundary

The implemented calibration, SRM, and reconstruction contracts are derived
from the local project RTL snapshots in `rtl/`:

- `sar_calib_ctrl_serial.sv`
- `srm_residue_estimator.sv`
- `sar_reconstruction.sv`

ADCToolbox is not the calibration algorithm. The MIT-licensed ADCToolbox 0.9.1
metric functions are reused only for standardized spectrum and ramp-histogram
analysis. See `behavior/THIRD_PARTY_NOTICES.md`.

## Formal Evidence

- Campaign status: `512/512` independent virtual chips complete.
- Decoder records: `2048`.
- Calibrated + SRM SNDR P01/median/P99:
  `89.680 / 91.018 / 91.533 dB`.
- Calibrated + SRM SFDR median: `108.776 dBc`.
- Calibrated + SRM INL peak-to-peak median/P95:
  `2.015 / 2.774 LSB`.
- Calibrated + SRM DNL peak-to-peak median/P95:
  `1.477 / 1.970 LSB`.
- Missing-code median/P95/max: `0 / 4 / 18`.
- High-resolution worst representative: `2` missing codes at 8 ramp samples
  per code.
- Python regression: `5 passed`.
- PDF release gate: PASS, 9 pages.

The result demonstrates a closed behavior-level signal chain. It is not
AMS, transistor-level, PVT, PEX, FPGA timing, or silicon-yield signoff.

## Reproduction

From the repository root:

```powershell
$py = "C:\Users\Administrator\Desktop\ADCToolbox_EVAL_20260728\envs\upstream-main\Scripts\python.exe"

& $py -m pytest analysis\full_sar_behavioral_20260729\test_full_sar_model.py -q
& $py analysis\full_sar_behavioral_20260729\run_campaign.py --chips 512 --workers 6
```

The campaign uses deterministic `SeedSequence` streams and one JSON checkpoint
per chip. Rerunning the command resumes completed points and rebuilds the
aggregate evidence.

## Main Files

- `behavior/full_sar_model.py`: complete behavior core.
- `behavior/run_campaign.py`: restartable campaign and report plots.
- `behavior/test_full_sar_model.py`: unit and short-loop regression.
- `behavior/outputs/summary.json`: authoritative aggregate result.
- `behavior/outputs/per_chip_decoder_metrics.csv`: all 2048 records.
- `behavior/outputs/highres_*.npz`: representative static evidence.
- `report/full_sar_behavioral_validation_cn.pdf`: Chinese technical report.
- `SHA256SUMS.txt`: integrity list for every package file except itself.
