# Physical CDAC Mismatch Revalidation

This folder is the qualified behavior-level validation area for the current
project foreground calibration, 22-decision SRM, and Q8 reconstruction path.
The calibration source of truth is the project RTL, not ADCToolbox or another
open-source calibration implementation.

## Qualified Scope

- Physical `6+4+5+5` segmented CDAC with bridge/parasitic matrix solving.
- Unit-cap mismatch is applied before effective weights are solved:
  `sigma_rel = sigma_unit / sqrt(Nunit)`.
- Project center: 8 fF unit cap, 1.2% unit-cap RMS mismatch, 2% node-parasitic
  and comparator-input-cap variation. These are archived project-MATLAB
  assumptions, not foundry PDK signoff values.
- Current RTL-equivalent bit 6-19 P/N recursive calibration with 32 P/N pairs.
- Current 22-decision stochastic SRM for dynamic FFT captures.
- Deterministic expected-count SRM for static DNL/INL ramps.
- Q8 signed reconstruction and signed 16-bit saturation.

The model intentionally disables ordinary sampling, normal-comparator,
reference, and settling noise so this experiment isolates mismatch removal.
Split-sampling VCM/AZ/flash/switch timing remains outside this L2 model.

## Formal Campaign

- 512 physical chips, 8192-point coherent FFT.
- Full-scale and `-1.72 dBFS` dynamic conditions.
- Full 16-bit ramp at 2 samples/code.
- 7 unit-cap mismatch points, 128 chips/point.
- 5 input-amplitude points, 128 chips.
- 6 decoder paths including current RTL, oracle, causal ablation, symmetric
  normalization, and a one-sided headroom-guard analysis candidate.

Key results:

- Direct ideal 16-bit quantizer: `98.079 dB` SNDR.
- Segmented CDAC with exact physical residue: `98.079 dB`.
- Deterministic expected-count SRM: `98.045 dB`.
- Stochastic 22-decision SRM median: `97.145 dB`.
- Current calibration full-scale median: `95.256 dB`.
- Current calibration backed-off median: `93.577 dB`.
- Current calibration full-scale minimum: `55.619 dB`, caused by rail clipping.
- One-sided headroom guard minimum: `93.129 dB`, with 512/512 above 90 dB.
- Current static median: DNL max `0.968 LSB`, INL max `0.993 LSB`,
  missing codes `0`; worst missing-code count remains `30`.

The headroom guard is not current RTL and is not a more accurate weight
calibrator. It only prevents global gain increases from consuming output rail
headroom.

## Run

```powershell
$py = "$HOME\Desktop\ADCToolbox_EVAL_20260728\envs"
$py = Join-Path $py "upstream-main\Scripts\python.exe"

& $py -m pytest `
  analysis\physical_cdac_mismatch_20260729\test_physical_cdac.py `
  analysis\physical_cdac_mismatch_20260729\test_revalidation.py -q

& $py analysis\physical_cdac_mismatch_20260729\run_revalidation.py `
  --chips 512 --sensitivity-chips 128 --amplitude-chips 128 --workers 6

powershell -ExecutionPolicy Bypass -File scripts\run_all_xsim.ps1
```

## Evidence

- `outputs_revalidation/summary.json`
- `outputs_revalidation/per_chip_main_metrics.csv`
- `outputs_revalidation/per_chip_physical_metrics.csv`
- `outputs_revalidation/per_chip_sigma_metrics.csv`
- `outputs_revalidation/per_chip_amplitude_metrics.csv`
- `report_revalidation/physical_cdac_revalidation_cn.pdf`
- `VALIDATION_REPORT_CN.md`
- `RUN_LOG.md`
- `SHA256SUMS_REVALIDATION.txt`

The symmetric-normalization v2 intermediate campaign is recoverable under
`archive/assumption_stress_tests/revalidation_v2_symmetric_sum_20260729/`.
