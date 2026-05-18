# Mixed-Signal Timing Contract

## 1. Scope

This document defines the timing assumptions between the SAR ADC analog front-end
(AFE), SAR calibration controller, SRM residue estimator, and reconstruction
datapath.

This is a **contract document**, not an implementation file. It records the
implicit assumptions the current RTL makes about when inputs are sampled and
what the integration-level timing obligations are.

> The current SAR ADC V3 core RTL assumes that comparator and SRM decision
> inputs are presented to the digital core with valid setup/hold timing
> relative to `clk`. They are **not** treated as arbitrary asynchronous GPIO
> signals inside the core RTL.

## 2. Clock and Reset Assumptions

| Signal      | Direction | Contract |
|-------------|-----------|----------|
| `clk`       | input     | Single digital core clock for the current RTL baseline |
| `rst_n`     | input     | Active-low reset, asynchronous assertion; release must be synchronized at the integration level for ASIC |
| `rst_n_btn` | input     | FPGA wrapper only; not part of the ASIC digital top |

Current core build assumes:

- `clk` is the only RTL clock domain.
- No internal CDC exists among the three core RTL modules.
- Any signal not synchronous to `clk` must be synchronized or converted into a
  timed pulse **before** entering the core.

## 3. Calibration Comparator Timing

### 3.1 Signals

| Signal            | Direction | Owner                    | Meaning |
|-------------------|-----------|--------------------------|---------|
| `dac_p_force`     | output    | digital core             | Forced DAC P-side calibration pattern |
| `dac_n_force`     | output    | digital core             | Forced DAC N-side calibration pattern |
| `comp_out`        | input     | analog comparator/wrapper | Comparator decision sampled by calibration controller |
| `calib_comp_out`  | input     | analog comparator/wrapper | Same role in ASIC digital top |
| `calib_mode_en`   | output    | digital core             | Calibration mode active indicator |
| `start_calib`     | input     | system control           | Starts foreground calibration |
| `calib_done`      | output    | digital core             | Calibration sequence completed |

### 3.2 Current RTL Assumption

The calibration controller assumes:

1. `dac_p_force` and `dac_n_force` are updated by the digital core.
2. The analog DAC/comparator path settles during the programmed wait interval
   (`COMP_WAIT_CYC` cycles).
3. `comp_out` is valid and stable before the clock edge where the controller
   samples it.
4. `comp_out` remains stable through the required hold time after that edge.

In other words, `comp_out` is treated as a **timed mixed-signal input**, not
as a free-running asynchronous GPIO.

### 3.3 Required Setup/Hold Contract

At the sampling edge:

```text
clk rising edge:         ↑
comp_out valid:     ----========----
                          ↑ sample here
```

The integration owner must guarantee:

| Parameter           | Requirement |
|---------------------|-------------|
| `t_setup_comp_out`  | `comp_out` valid before the sampling clock edge |
| `t_hold_comp_out`   | `comp_out` stable after the sampling clock edge |
| `t_dac_settle`      | DAC force outputs and analog comparator input settle before `comp_out` is sampled |
| `t_comp_regen`      | Comparator regeneration completes before `comp_out` is sampled |

If these assumptions cannot be guaranteed, `comp_out` must be wrapped by a
synchronizer, handshake, or explicit comparator-done protocol **outside** the
current core RTL.

## 4. Why a Blind Two-Flop Synchronizer Is Not Automatically Correct

A two-flop synchronizer is appropriate for arbitrary asynchronous level signals,
but it changes latency by one or more clock cycles.

For SAR calibration and bit-cycling, this may be incorrect because the
comparator decision is associated with a specific DAC trial state.

Therefore:

- If `comp_out` is truly asynchronous and latency-insensitive, a two-flop
  synchronizer may be added at the **wrapper** level.
- If `comp_out` corresponds to a specific SAR/DAC trial, the correct solution
  is a timed sampling edge or a comparator-done handshake.
- The core RTL must **not** silently insert extra decision latency without
  updating the SAR/calibration timing model.

## 5. SRM Residue Timing

### 5.1 Signals

| Signal               | Direction | Meaning |
|----------------------|-----------|---------|
| `srm_start`          | input     | Starts SRM decision accumulation |
| `srm_decision_valid` | input     | Indicates one SRM decision bit is valid |
| `srm_decision_bit`   | input     | SRM comparator decision bit |
| `srm_busy`           | output    | SRM estimator is collecting decisions |
| `srm_done`           | output    | SRM residue is ready |
| `srm_residue_q`      | output    | Q8 residue correction |

### 5.2 Contract

The SRM estimator assumes:

1. `srm_decision_valid` is synchronous to `clk`.
2. `srm_decision_bit` is valid when `srm_decision_valid` is high.
3. Exactly one decision is consumed per valid pulse.
4. `DECISION_COUNT = 22` decisions are collected per residue estimate.

If SRM decisions come directly from an asynchronous comparator, the wrapper
must convert them into synchronous `srm_decision_valid` / `srm_decision_bit`
pulses.

## 6. Reconstruction Timing

### 6.1 Signals

| Signal           | Direction | Meaning |
|------------------|-----------|---------|
| `data_valid_in`  | input     | Raw SAR code valid |
| `raw_bits`       | input     | SAR raw decision vector |
| `w_wr_en`        | input     | Calibration weight write enable |
| `w_wr_addr`      | input     | Calibration weight address |
| `w_wr_data`      | input     | Calibration weight data |
| `srm_residue`    | input     | Q8 SRM residue correction |
| `adc_dout`       | output    | Reconstructed ADC output |
| `data_valid_out` | output    | Reconstructed output valid |

### 6.2 Contract

The reconstruction datapath assumes:

1. `raw_bits` is stable when `data_valid_in` is asserted.
2. `w_wr_en`, `w_wr_addr`, and `w_wr_data` are synchronous to `clk` (driven by
   the calibration controller inside the same clock domain).
3. `srm_residue` is synchronous to `clk` and corresponds to the conversion
   being reconstructed.
4. `data_valid_out` marks the valid reconstructed output after the internal
   two-stage pipeline latency.

## 7. FPGA Wrapper Contract

`sar_calib_fpga_top` is **FPGA-only**.

It may include:

- button/switch inputs,
- LED outputs,
- debug taps (`(* mark_debug = "true" *)`),
- deterministic comparator stubs,
- future ILA integration.

It must **not** be used as the ASIC digital top.

The current FPGA comparator stub (`comp_out_stub = 1'b0`) is for build closure
only and does not validate real mixed-signal timing.

## 8. ASIC Digital Top Contract

`sar_adc_digital_top` is the **ASIC-oriented digital integration skeleton**.

It must **not** include:

- FPGA buttons,
- LEDs,
- ILA IP,
- board-specific constraints.

Before tapeout, the ASIC integration must define:

- comparator clocking,
- DAC switching phase timing,
- sampling/hold timing,
- calibration / normal / SRM mode arbitration,
- reset synchronization (synchronous de-assertion of `rst_n`),
- scan / DFT integration,
- timing constraints in SDC format.

## 9. CDC Position

Current CDC classification:

| Signal | Current Classification | Required Action |
|--------|------------------------|-----------------|
| `clk` | single core clock | no CDC inside core |
| `rst_n` | async reset | ASIC requires synchronized release |
| `comp_out` | timed mixed-signal input | setup/hold contract, or wrapper-level synchronizer/handshake |
| `srm_decision_bit` | synchronous when valid | wrapper must synchronize if source is async |
| `raw_bits` | synchronous when `data_valid_in` is high | SAR controller must guarantee stability |
| `w_wr_*` | synchronous internal bus | no CDC |
| `srm_residue` | synchronous internal bus | no CDC |

## 10. Open Items

The following items are **not** closed by this document and must be resolved
before tapeout:

1. Exact comparator regeneration timing across PVT and mismatch.
2. Exact DAC settling time across PVT and mismatch.
3. Final SAR bit-cycle schedule.
4. Whether `comp_out` requires a wrapper-level synchronizer, timed latch, or
   comparator-done handshake in the target system.
5. ASIC SDC constraints.
6. Gate-level and mixed-signal co-simulation timing signoff.
