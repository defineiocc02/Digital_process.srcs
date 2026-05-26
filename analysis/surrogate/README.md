# Huang 2025 Calibration Convergence Surrogate

This directory contains a bounded Python analysis model for the paper-inspired
calibration averaging trend:

```text
calibration measurement noise + averaging count
    -> weight-estimation uncertainty
    -> quantized 16-bit SNDR/SFDR/ENOB trend
```

## Entry Point

```powershell
python analysis\surrogate\replicate_huang2025_calibration_convergence.py
```

Generated result files are placed under `analysis/surrogate/outputs/` and are
ignored by Git.  Use `--quick` for a deterministic smoke run.

## Engineering Boundary

This model is not a transistor-level ADC reproduction, an analog CDAC
extraction, or an RTL-equivalent calibration golden model.  It deliberately
does not implement P/N calibration switching, recursive controller state
transitions, SRM residue LUT operation, or mixed-signal non-idealities.

The model adds two controls that are required before interpreting its trends:

- FFT metrics are computed only after explicit 16-bit output quantization.
- The `111 uVrms / 80 uV` and `38 uVrms / 80 uV` paper-referenced noise
  anchors are applied in external output-LSB units, not in the smallest
  reconstruction proxy-weight unit.

The script also emits a proxy qualification diagnostic and an RTL-Q8 direct
mapping saturation diagnostic.  These prevent the reconstruction-domain table
from being presented as a verified analog conversion vector.

## Next Step Toward RTL Equivalence

A true behavioral golden model should implement the sequence in
`rtl/sar_calib_ctrl_serial.sv`: P/N comparator measurements, recursive Q8
writeback, top-bit protection, and the explicit relation between effective
measurement count and `AVG_LOOPS`.
