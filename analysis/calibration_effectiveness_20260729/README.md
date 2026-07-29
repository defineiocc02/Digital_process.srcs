# Current On-Chip Calibration Effectiveness Validation

This folder validates the calibration scheme implemented in the current project
folder. The calibration algorithm under test is **not** an open-source
ADCToolbox calibration routine.

## Source Of Truth

| Layer | Authoritative project file |
| --- | --- |
| On-chip foreground calibration FSM | `rtl/sar_calib_ctrl_serial.sv` |
| Q8 reconstruction arithmetic | `rtl/sar_reconstruction.sv` |
| Fixed-point contract | `docs/FIXED_POINT_CONTRACT.md` |
| RTL calibration TB | `Digital_process/Digital_process.srcs/sim_1/new/tb_gain_comp_check_lsb.sv` |
| Q8 reconstruction TB | `Digital_process/Digital_process.srcs/sim_1/new/tb_recon_q8_split_weights.sv` |

The Python model in this folder mirrors the project RTL behavior:

- target bits `6..19`;
- trusted LSB section `0..5`;
- P/N measurement phases;
- comparator offset and noise during calibration;
- bit-18/bit-19 protection compensation;
- recursive Q8 writeback;
- `sar_reconstruction.sv` signed `+W/-W`, `/2`, Q8 rounding, and saturation.

## Role Of 12-Bit Project And ADCToolbox Experience

The 12-bit project and ADCToolbox package are used only as validation-method
references:

- decode the same physical decision stream with nominal, calibrated, and oracle
  weights;
- separate weight error, static transfer error, and dynamic FFT evidence;
- avoid claiming that dynamic SNDR alone proves static INL/DNL closure;
- label behavioral evidence separately from RTL, AMS, transistor, PVT, PEX, and
  silicon evidence.

They are **not** used as the calibration algorithm in this folder. The current
project's on-chip calibration scheme remains the RTL scheme in
`sar_calib_ctrl_serial.sv`.

## Run

```powershell
python analysis\calibration_effectiveness_20260729\validate_current_calibration.py
```

Quick smoke run:

```powershell
python analysis\calibration_effectiveness_20260729\validate_current_calibration.py --quick
```

Generated outputs:

- `outputs/summary.json`
- `outputs/per_chip_results.csv`
- `outputs/fig_dynamic_sndr_median.png`
- `outputs/fig_weight_rmse.png`

## Current Evidence Boundary

This is a behavioral RTL-equivalent validation. It does not replace:

- Vivado/XSIM RTL simulation;
- mixed-signal AMS simulation with real comparator timing;
- transistor-level Spectre;
- PVT/Monte Carlo with a foundry mismatch model;
- post-layout PEX or silicon measurement.

The key claim supported here is narrower and explicit:

> Under the modeled split-cap weight mismatch, comparator offset, and calibration
> noise conditions, the current project foreground calibration algorithm
> substantially improves the digital reconstruction weight accuracy and closes
> most of the gap to a physical-weight oracle when all decoders use the same
> physical decision stream.
