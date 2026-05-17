# Reproduction Report: Huang Split-Sampling SAR ADC Digital Algorithm

Date: 2026-05-18

## Source Material

- `0849 - Huang et al. - 2025 - A 5-MS/s 16-bit low-noise and low-power split sampling SAR ADC with eased driving burden.pdf`
- `0764 - Huang - 2024 - Advanced clock multiplier and SAR ADC design techniques for high-resolution signal chain systems.pdf`

The digital reproduction focuses on the algorithmic boundary described around
SRM-assisted self-calibration and bit-weight reconstruction. It does not attempt
to reproduce transistor-level sampling, autozero, flash ADC, or analog noise
circuits.

## Extracted Digital Algorithm

The papers describe three digital responsibilities:

1. **Self-calibration of bit weights**
   - Use the 6-bit LSB section as a reference DAC.
   - Measure upper-bit weights recursively.
   - Use positive and negative measurement directions so preamplifier/latch
     offset cancels.
   - Average repeated measurements to suppress noise.
   - Apply special switching for the highest bits to keep top-plate swing in
     range.

2. **Digital reconstruction**
   - Reconstruct the ADC code from raw SAR decisions and calibrated weights.
   - Normalize the differential weighted sum.
   - Round and saturate to signed 16-bit output.

3. **Statistical residue measurement**
   - Perform 22 extra noisy comparator decisions after SAR conversion.
   - Treat the count of ones as a probability estimate of residue polarity and
     magnitude.
   - Map the count to a signed residue correction and add it before final output
     quantization.

## Implemented RTL Mapping

| Algorithm item | RTL |
| --- | --- |
| Recursive weight self-calibration | `sar_calib_ctrl_serial.sv` |
| Offset-canceling positive/negative measurement | `sar_calib_ctrl_serial.sv` |
| Top-bit protection switching | `sar_calib_ctrl_serial.sv` |
| Weighted digital reconstruction | `sar_reconstruction.sv` |
| SRM residue correction injection | `sar_reconstruction.sv` |
| 22-decision SRM count-to-residue estimator | `srm_residue_estimator.sv` |

## SRM Estimator Details

The SRM estimator uses `DECISION_COUNT = 22`. For a count `c`, the LUT maps the
smoothed probability `(c + 0.5) / 23` to a signed residue assuming comparator
noise `sigma = 0.5 LSB`. The output is Q8 fixed-point by default.

The implemented LUT is symmetric:

```text
[-258, -194, -158, -131, -110, -91, -74, -58, -43, -28, -14,
 0,
 14, 28, 43, 58, 74, 91, 110, 131, 158, 194, 258]
```

This is a compact reproduction of the archived MATLAB `erf_inv` LUT concept,
adapted to the paper's 22-decision SRM phase.

## Vivado Simulation Setup

Vivado installation:

```text
D:\Academic\Vivado2018\Vivado\2018.3\bin
```

Reusable Codex Skill:

```text
C:\Users\Administrator\.codex\skills\vivado-xsim
```

The tests were run with `xvlog.bat`, `xelab.bat`, and `xsim.bat` in isolated
`sim_work/` directories.

## Results

### `tb_srm_residue_estimator`

Status: PASS

Checked counts:

| Ones count | Residue Q8 |
| --- | ---: |
| 0 | -258 |
| 1 | -194 |
| 11 | 0 |
| 21 | 194 |
| 22 | 258 |

The test also checks edge and center symmetry.

### `tb_sar_recon`

Status: PASS

- Linearity: 20 swept input points all matched the expected signed 16-bit code.
- Weight update: +10% MSB weight perturbation shifted output as expected.
- Throughput: 5 continuous input samples produced 5 outputs.
- SRM injection: `srm_residue = +256` shifted output by +1 code and
  `srm_residue = -256` shifted output by -1 code.

### `tb_gain_comp_check_lsb`

Status: PASS

Five Monte Carlo runs passed the `< 0.5 LSB` residual error criterion.

| Run | Max residual INL error |
| --- | ---: |
| 0 | 0.3127 LSB |
| 1 | 0.4261 LSB |
| 2 | 0.3315 LSB |
| 3 | 0.3241 LSB |
| 4 | 0.4532 LSB |

Worst observed result: `0.4532 LSB`, still below the criterion.

## Known Limitations

- The SRM analog probability source is not implemented as transistor-level
  circuitry; it is represented by comparator decision streams in testbench.
- The split-sampling capacitor network and autozero bandwidth/noise model are
  not synthesized RTL blocks.
- `tb_gain_comp_check_lsb.sv` still has a Vivado 2018.3 style warning about
  explicit `automatic/static` declaration for a testbench variable.

## Conclusion

The active project now reproduces the complete digital algorithm boundary:
foreground bit-weight self-calibration, calibrated reconstruction, and SRM
count-to-residue correction. All reproduction testbenches pass in Vivado 2018.3
XSIM.
