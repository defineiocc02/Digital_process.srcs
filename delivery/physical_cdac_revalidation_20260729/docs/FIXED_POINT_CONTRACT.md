# Fixed-Point Contract

Date: 2026-05-18

This document defines the fixed-point units used by the active SAR ADC digital
reproduction core. It exists to prevent the binary-normalized reconstruction
smoke test from being confused with the split-capacitor Q8 calibration path.

## 1. Global Definitions

| Item | Value | Meaning |
| --- | ---: | --- |
| `CAP_NUM` | 20 | Number of raw SAR decision / capacitor-weight entries |
| `OUTPUT_WIDTH` | 16 | Signed output code width |
| `FRAC_BITS` | 8 | Q8 fractional scale in reconstruction arithmetic |
| `Q8_ONE_CODE` | 256 | One final output-code LSB in the Q8 reconstruction domain |

Unless a testbench states otherwise, signed fixed-point weights use Q8 units:

```text
integer_value = physical_code_lsb * 2^FRAC_BITS
              = physical_code_lsb * 256
```

## 2. Reconstruction Arithmetic

`sar_reconstruction.sv` implements the following integer data path:

```text
weighted_sum = sum(raw_bits[i] ? +weight_ram[i] : -weight_ram[i])
normalized   = (weighted_sum >>> 1) + srm_residue
rounded      = normalized + 2^(FRAC_BITS - 1)
shifted      = rounded >>> FRAC_BITS
adc_dout     = saturate_to_int16(shifted)
```

The `/2` term is part of the current differential reconstruction convention:
the raw-bit contribution uses a two-sided `+W_i / -W_i` sum, so the final
single-ended signed output-code domain is half of that differential span.

Important consequence:

```text
srm_residue = +256
```

means `+1` final output-code LSB when the output is not saturated.

## 3. Interface Units

| Signal | Producer | Consumer | Unit |
| --- | --- | --- | --- |
| `w_wr_data` | calibration controller or TB | `sar_reconstruction.weight_ram` | signed Q8 reconstruction weight |
| `weight_ram[i]` | internal reconstruction RAM | weighted sum | signed Q8 reconstruction weight |
| `srm_residue` | SRM estimator or TB | reconstruction post-sum correction | signed Q8 output-code residue |
| `adc_dout` | reconstruction | downstream digital user | signed two's-complement 16-bit output code |

`srm_residue_estimator.sv` outputs the same Q8 unit expected by
`sar_reconstruction.sv`.

## 4. Binary-Normalized Smoke Test Contract

`tb_sar_recon_binary_norm.sv` is intentionally not a split-capacitor
calibration consistency test. It verifies a simpler ideal binary raw-code model:

```text
raw_bits      = ideal 20-bit binary SAR code
output        = signed 16-bit normalized ADC code
weight unit   = Q8 arithmetic, pre-normalized to the 16-bit output range
```

The ideal binary test weight is:

```text
W_i = 2^i * 2^(OUTPUT_WIDTH + FRAC_BITS - CAP_NUM)
    = 2^i * 2^(16 + 8 - 20)
    = 2^i * 16
```

So the historical `<< 4` scale was mathematically valid for this TB. It is now
named as `BINARY_NORM_SHIFT` to avoid being mistaken for the calibrated Q8
split-cap weight scale.

## 5. Split-Cap Q8 Contract

`tb_recon_q8_split_weights.sv` verifies the path that the binary-normalized TB
does not cover:

```text
split-cap ideal weights in Q8
    -> sar_reconstruction.weight_ram
    -> fixed-point weighted_sum / 2
    -> Q8 SRM residue injection
    -> signed 16-bit output
```

The current ideal split-cap weight table is:

| Bit | Weight (output LSB) | Q8 integer |
| ---: | ---: | ---: |
| 0 | 1.00 | 256 |
| 1 | 2.00 | 512 |
| 2 | 4.00 | 1024 |
| 3 | 8.00 | 2048 |
| 4 | 16.00 | 4096 |
| 5 | 32.00 | 8192 |
| 6 | 33.53 | 8584 |
| 7 | 67.05 | 17165 |
| 8 | 134.10 | 34330 |
| 9 | 268.20 | 68659 |
| 10 | 316.91 | 81129 |
| 11 | 316.91 | 81129 |
| 12 | 633.81 | 162255 |
| 13 | 1267.63 | 324513 |
| 14 | 2535.25 | 649024 |
| 15 | 5031.09 | 1287959 |
| 16 | 5031.09 | 1287959 |
| 17 | 10062.17 | 2575916 |
| 18 | 20124.35 | 5151834 |
| 19 | 40248.69 | 10303665 |

The split-cap table is used as a contract test vector. The exact analog
derivation, capacitor segmentation, and gain calibration policy remain part of
the mixed-signal model and should be updated if the physical CDAC model changes.

## 6. Rounding Convention

The current RTL uses:

```text
rounded = normalized + 2^(FRAC_BITS - 1)
```

before arithmetic right shift. This is bit-exactly mirrored in the TB manual
models. It is simple and matches the current regression baseline, but it is not
a symmetric round-half-away-from-zero rule for negative values.

If this convention changes, update:

- `sar_reconstruction.sv`
- `tb_sar_recon_binary_norm.sv`
- `tb_recon_q8_split_weights.sv`
- reproduction and verification reports

## 7. Known Limits

- The active RTL still lacks a full system top that arbitrates normal SAR
  conversion, calibration, SRM decision capture, and reconstruction.
- `sar_reconstruction.sv` reset initializes only the trusted low bits; upper
  calibrated weights must be loaded before normal use.
- The split-cap Q8 TB proves fixed-point consistency, not final ADC SNDR/SFDR,
  INL/DNL, or silicon margin.
