# Physical CDAC Mismatch Validation

This experiment replaces the withdrawn direct effective-weight 3% stress test
with a physical 6+4+5+5 segmented-CDAC mismatch model.

## Model Boundary

- Physical bit capacitors and bridge capacitors are perturbed before solving
  effective decision weights.
- A capacitor containing `N` unit capacitors uses
  `sigma_rel = sigma_unit / sqrt(N)`.
- The project MATLAB center point is `1.2% rms` per 8 fF unit capacitor,
  `2% rms` node-parasitic variation, and `2% rms` comparator-input-capacitance
  variation. These are project assumptions, not foundry PDK values.
- Dynamic conversion disables sampling, normal-comparator, reference, and
  settling noise. The paper-faithful 22-decision stochastic SRM remains active.
- Static ramp analysis uses deterministic expected-count SRM so random empty
  bins are not misreported as DNL or missing codes.

## Run

```powershell
$py = "C:\Users\Administrator\Desktop\ADCToolbox_EVAL_20260728\envs\upstream-main\Scripts\python.exe"
& $py -m pytest analysis\physical_cdac_mismatch_20260729\test_physical_cdac.py -q
& $py analysis\physical_cdac_mismatch_20260729\run_physical_mismatch.py --chips 512 --sensitivity-chips 128 --workers 6
& $py analysis\physical_cdac_mismatch_20260729\analyze_srm_precision_profiles.py
```

## Acceptance Baselines

- Ideal uniform 16-bit quantizer: `98.079 dB` SNDR.
- Nominal segmented CDAC plus deterministic expected-count SRM: `98.045 dB`.
- Current RTL 22-decision stochastic SRM: approximately `97.15 dB`.

The deterministic result is an arithmetic closure gate, not a claim about a
single physical conversion. The stochastic result is the current RTL-realistic
finite-sample profile.

## Main Evidence

- `outputs/summary.json`
- `outputs/per_chip_decoder_metrics.csv`
- `outputs/per_chip_physical_metrics.csv`
- `outputs/sensitivity_summary.csv`
- `outputs/srm_precision_profiles.json`
- `VALIDATION_REPORT_CN.md`

Generated logs, smoke outputs, and Python caches are ignored. The qualified
CSV/JSON/PNG/PDF evidence under `outputs/` is versioned.
