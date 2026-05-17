# FPGA and ASIC Signoff Review

Date: 2026-05-18

Scope: active digital core RTL and unit testbenches for SAR ADC calibration,
digital reconstruction, and SRM residue estimation.

## Executive Result

The active core package passes Vivado 2018.3 XSIM unit verification and
standalone Artix-7 synthesis checks. This is a strong digital-core reproduction
result, but it is not a complete FPGA bitstream signoff or ASIC tapeout signoff.
The remaining risks are integration constraints, analog boundary assumptions,
clock/reset treatment, and ASIC implementation signoff.

## Verified RTL Set

| RTL | Role |
| --- | --- |
| `Digital_process/Digital_process.srcs/sources_1/new/sar_reconstruction.sv` | Calibrated fixed-point reconstruction with SRM residue injection |
| `Digital_process/Digital_process.srcs/sources_1/new/sar_calib_ctrl_serial.sv` | Foreground recursive capacitor weight calibration controller |
| `Digital_process/Digital_process.srcs/sources_1/new/srm_residue_estimator.sv` | 22-decision SRM count-to-residue digital estimator |

## XSIM Results

Vivado install:

```text
D:\Academic\Vivado2018\Vivado\2018.3\bin
```

| Testbench | Result | Key evidence |
| --- | --- | --- |
| `tb_sar_recon` | PASS | 48 checks, 0 failed; linearity, weight update, pipeline throughput, SRM injection |
| `tb_srm_residue_estimator` | PASS | 17 checks, 0 failed; LUT edge/center/symmetry cases |
| `tb_gain_comp_check_lsb` | PASS | 10 checks, 0 failed; 5 Monte Carlo runs; worst residual error `0.4937 LSB` |

Generated logs are under `sim_work/<tb_name>/xsim.log`.

## Synthesis Results

Command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run_core_synth_checks.ps1
```

Target part: `xc7a35tfgg484-2`

| Top | Synth result | LUT | FF | BRAM | DSP | 100 MHz WNS |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| `sar_reconstruction` | PASS | 950 | 818 | 0 | 0 | 3.999 ns |
| `srm_residue_estimator` | PASS | 26 | 22 | 0 | 0 | 7.480 ns |
| `sar_calib_ctrl_serial` | PASS | 511 | 821 | 0 | 0 | 5.450 ns |

Generated reports and checkpoints are under `sim_work/synth/<top>/`.

Environment notes:

- Vivado reports `Common 17-741` because the local Tcl store is not writable.
  This is a machine setup warning and does not change synthesized netlists.
- Standalone synthesis applies a simple 100 MHz clock in the Tcl flow. It does
  not validate board pinout or final top-level I/O timing.

## FPGA Readiness

The core RTL is suitable for FPGA integration experiments after wrapper and
constraint cleanup.

Known FPGA integration issues:

- The current active XDC is board-wrapper oriented and references ports such as
  `rst_n_btn`, `start_sw`, and `done_led`; those are not ports of the minimal
  core tops. Use it only as a historical board hint, not as final signoff XDC.
- `check_timing` reports no unconstrained internal register endpoints after the
  script adds `clk_100m`, but top-level input and output delays are still
  unspecified. Final FPGA closure needs real ADC interface timing budgets.
- The calibration controller samples `comp_out` with one register. If the
  comparator decision is asynchronous to `clk`, the integration wrapper must
  define a settling contract or add synchronization/metastability handling.
- `start_calib`, reset buttons, and external debug controls must be debounced
  and synchronized at the FPGA boundary.
- No complete ADC system wrapper is active in the minimal project. Bitstream
  generation needs a deliberate wrapper that connects SAR sequencer, comparator,
  calibration, SRM, and reconstruction timing.

## ASIC Tapeout Readiness

The RTL is a useful ASIC prototype, but it is not tapeout-ready without a normal
ASIC signoff flow.

Required ASIC work before tapeout:

- Run lint, CDC/RDC, formal equivalence, gate-level simulation with SDF, STA
  across PVT corners, and reset-domain checks.
- Define whether active-low asynchronous reset is acceptable for the target DFT
  methodology. If not, convert or wrap reset release with a synchronizer.
- Qualify the SystemVerilog style with the ASIC synthesis tool. Vivado accepts
  the unpacked arrays, functions, casts, enums, and loops used here; the ASIC
  front-end must be checked explicitly.
- Add scan strategy, test mode controls, clock gating policy, power intent,
  isolation/retention rules if needed, and production test access.
- Replace the behavioral analog TB assumptions with transistor-level or
  mixed-signal verification for comparator offset, noise, DAC settling, and SRM
  latch statistics.
- Expand Monte Carlo coverage. The current digital reproduction passes 5 seeded
  runs, but the worst run is close to the `0.5 LSB` limit, so process/noise
  margin should be quantified over many more seeds and analog corners.

## Maintenance Decision

Keep the active repo small:

- Preserve only the three core RTL files, three TB files, docs, scripts, and the
  Vivado project shell.
- Keep obsolete wrappers, MATLAB experiments, and duplicate RTL/TB files in
  `archive/` for recovery and historical comparison.
- Treat `delivery/sar_adc_v3_digital_core_2026-05-18/` as the frozen handoff
  package for this verified state.
