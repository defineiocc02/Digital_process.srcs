# Physical CDAC Revalidation Delivery

This package freezes the source, testbench, behavioral model, formal evidence,
and report used for the 2026-07-29 SAR ADC digital-core revalidation.

## Scope

- Physical 6+4+5+5 segmented-CDAC proxy with bridge capacitors and node parasitics.
- Area-scaled capacitor mismatch with a 1.2% unit-cap center case.
- Twenty differential SAR decisions, current P/N recursive foreground
  calibration, 22-decision SRM, Q8 reconstruction, and signed 16-bit output.
- 512-chip main campaign, full 16-bit static ramp, mismatch sensitivity sweep,
  amplitude/headroom sweep, deterministic replay, and Vivado 2018.3 XSIM.

The current RTL-equivalent decoder remains the implementation baseline. The
one-sided headroom guard is an analysis candidate only and is not present in
the frozen RTL.

## Reproduce

Run from this package root with Python 3.10 or later:

```powershell
python -m pip install -r analysis\full_sar_behavioral_20260729\requirements.txt
python -m pytest `
  analysis\physical_cdac_mismatch_20260729\test_physical_cdac.py `
  analysis\physical_cdac_mismatch_20260729\test_revalidation.py -q
python analysis\physical_cdac_mismatch_20260729\run_revalidation.py `
  --chips 512 --sensitivity-chips 128 --amplitude-chips 128 --workers 6
```

The runner writes a new `outputs_revalidation/` directory beside the script.
The frozen formal outputs are in `evidence/`.

Vivado XSIM can be run directly from this package root; the packaged runner
detects the frozen `rtl/` and `tb/` layout:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_all_xsim.ps1
```

## Evidence Boundary

The no-noise conversion experiment disables ordinary sampling, comparator,
reference, and settling noise. Stochastic behavior remains only in the finite
22-decision SRM estimator where explicitly selected. The package does not
claim transistor-level reproduction of split sampling, VCM switching, the
initial 2-bit flash decision, reference settling, or comparator metastability.

Read `report/physical_cdac_revalidation_cn.pdf` for the full mathematical,
algorithmic, verification, FPGA/ASIC, and maintenance analysis.
