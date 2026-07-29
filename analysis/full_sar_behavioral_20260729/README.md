# Complete SAR Behavioral Validation

This directory closes the system-level behavioral path that was intentionally
out of scope in `analysis/calibration_effectiveness_20260729`.

## What Is Modeled

```text
sampled input + sampling noise
    -> 20 signed differential SAR decisions
    -> physical CDAC residue
    -> 22 noisy SRM decisions
    -> RTL count-to-Q8 SRM LUT
    -> nominal / calibrated / oracle digital weights
    -> RTL-equivalent signed Q8 reconstruction
    -> FFT and full-range ramp characterization
```

The foreground-calibration algorithm is still the current project algorithm:

- `rtl/sar_calib_ctrl_serial.sv`
- `rtl/srm_residue_estimator.sv`
- `rtl/sar_reconstruction.sv`

ADCToolbox 0.9.1 is reused only for standardized FFT and ramp-histogram
DNL/INL extraction.

## Formal Campaign

The requested **512 points** are defined as 512 deterministic independent
virtual chips. Every point runs:

- physical weight mismatch;
- complete recursive foreground calibration;
- 8192-sample coherent dynamic conversion;
- 20 SAR decisions per conversion;
- 22 SRM observations per conversion;
- nominal, calibrated, calibrated+SRM, and oracle+SRM decoding;
- SNDR, SNR, SFDR, THD, and ENOB;
- a full 16-bit ramp with two samples per code;
- DNL, INL, missing-code, and saturation analysis.

Best, median, and worst calibrated chips are rerun at eight ramp samples per
code for higher-resolution static cross-checks.

The dynamic sine path includes sampling/comparator noise and stochastic SRM
decisions. The static ramp path disables random noise and uses the rounded
expected 22-decision SRM count so that two samples/code characterize the
deterministic transfer curve instead of producing Monte-Carlo empty bins.
INL/DNL are endpoint corrected over each decoder's exercised output span;
global gain and offset are reported separately from linearity.

## Run

Use the reviewed ADCToolbox environment:

```powershell
$py = "C:\Users\Administrator\Desktop\ADCToolbox_EVAL_20260728\envs\upstream-main\Scripts\python.exe"
& $py -m pytest analysis\full_sar_behavioral_20260729\test_full_sar_model.py -q
& $py analysis\full_sar_behavioral_20260729\run_campaign.py --chips 512 --workers 6
```

The campaign is checkpointed under `outputs/checkpoints`. Running the same
command again resumes unfinished chips.

## Evidence Boundary

This is a complete system-level behavioral loop, not an AMS or transistor
signoff. The effective weight table is the active reconstruction contract, not
a schematic-extracted bridge-capacitor network. Reference settling, charge
injection, comparator metastability timing, PVT, PEX, and silicon yield remain
later mixed-signal verification stages.
