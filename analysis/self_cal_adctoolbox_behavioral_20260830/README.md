# 16-bit On-Chip Self-Calibration Behavioral Experiment

This package validates the project's **16-bit SAR on-chip foreground
self-calibration** against a deterministic physical split-CDAC mismatch proxy.

Detailed Chinese engineering report:
`SELF_CAL_BEHAVIORAL_REPORT_CN.md`. Independent three-pass toolbox audit:
`reviews/REVIEW_01_ADCTOOLBOX_AUDIT_CN.md`.

## Algorithm Under Test

The primary algorithm is the local project algorithm:

```text
6-bit trusted LSB reference section
  -> P/N comparator measurements
  -> 32 offset-cancelled pairs per target
  -> recursive bit6..bit19 calibration
  -> bit18/bit19 protected search
  -> signed Q8 weight writeback
  -> 20-decision normal conversion
  -> optional 22-decision SRM residue estimate
  -> signed 16-bit reconstruction
```

The executable behavioral source is reused from
`analysis/full_sar_behavioral_20260729/full_sar_model.py`, which mirrors the
current RTL. The physical mismatch realization is reused from
`analysis/physical_cdac_mismatch_20260729/physical_cdac.py`.

## ADCToolbox Boundary

ADCToolbox is used for:

- SNDR, SNR, SFDR, THD, and ENOB extraction;
- ramp-histogram DNL/INL extraction;
- bit-matrix rank and conditioning diagnostics;
- one external sine-fit foreground-calibration comparison.

The sine-fit result is always named
`ADCTOOLBOX_SINE_EXTERNAL_BASELINE`. It needs a coherent external tone and is
not the on-chip self-calibration algorithm.

## Test Conditions

- 16-bit signed output, 20 raw decisions, Q8 weights;
- physical 6+4+5+5 segmented CDAC proxy;
- 1.2% unit-cap sigma with bridge-cap and parasitic variation;
- normal-conversion sampling, comparator, reference, and settling noise off;
- calibration comparator offset `5 LSB`, noise `0.5 LSB`;
- 32 P/N pairs for every calibrated bit;
- independent external-sine train and test frequencies;
- full 16-bit deterministic ramp, two samples per code;
- expected-count and stochastic 22-decision SRM results reported separately;
- a separate paired SRM noise-reduction ablation with `0.5 LSB` normal and
  SRM-observation comparator noise, 8192-point captures, and 32 noise repeats.

The first experiment isolates mismatch and residue information with ordinary
normal-conversion noise disabled. The paired ablation is the evidence for SRM
noise reduction: SRM on/off decode the exact same noisy 20-decision raw-bit
stream. It does not model split-sampling kT/C cancellation or the paper's full
transistor-level `111 to 38 uVrms` noise budget.

## Run

```powershell
$py = "C:\Users\Administrator\Desktop\ADCToolbox_EVAL_20260728\envs\upstream-main\Scripts\python.exe"
& $py -m pytest analysis\self_cal_adctoolbox_behavioral_20260830\test_self_cal_behavioral.py -q
& $py analysis\self_cal_adctoolbox_behavioral_20260830\run_self_cal_behavioral.py
```

Generated evidence is written to `outputs/`:

- `summary.json`: configuration, provenance, metrics, and evidence boundary;
- `metrics.csv`: dynamic and static metrics for every decoder;
- `weights.csv`: nominal, physical, on-chip self-cal, and external-fit weights;
- `srm_noise_ablation.csv`: all 32 paired noisy SRM on/off repeats;
- `calibration_trace.json`: per-target recursive self-calibration trace;
- `fig_weight_error.png`, `fig_spectrum_compare.png`,
  `fig_inl_compare.png`, `fig_calibration_trace.png`, and
  `fig_srm_noise_ablation.png`.

This is a behavior-level verification package. It is not an AMS, PVT, PEX,
STA, DRC/LVS, or silicon-yield signoff result.

## Qualified Reference Run

The frozen chip-17 run completed with `5 passed` integration tests. Its direct
ideal 16-bit control measured 98.093 dB SNDR against the 98.080 dB theoretical
anchor. With normal-conversion random noise disabled, the project on-chip
self-cal improved SNDR from 61.630 dB to 93.433 dB; deterministic expected SRM
raised it to 95.437 dB. In the separate paired comparator-noise ablation,
22-decision SRM raised mean oracle SNDR from 90.532 dB to 95.888 dB
(`+5.356 dB`) and project-self-cal SNDR from 89.716 dB to 93.888 dB
(`+4.172 dB`). See `outputs/summary.json` for complete provenance and evidence
boundaries.
