# Current Calibration Validation Delivery Package

Date: 2026-07-29

This package validates the current on-chip foreground calibration algorithm in this repository.

## Source-of-Truth Boundary

The calibration algorithm under validation is the current project RTL:

- `rtl/sar_calib_ctrl_serial.sv`: on-chip foreground bit-weight calibration controller.
- `rtl/sar_reconstruction.sv`: Q8 weighted reconstruction path.
- `rtl/srm_residue_estimator.sv`: SRM residue estimator used by the reconstruction contract.

External projects and open-source libraries were used only as verification-method references. They are not the implemented calibration algorithm for this package.

## Main Evidence

- Behavior-level validation: `behavior/validate_current_calibration.py`
- Behavior outputs: `behavior/outputs/summary.json`, CSV, and figures.
- RTL-level evidence: `logs/RTL_XSIM_SUMMARY.md`
- Academic report: `docs/current_calibration_validation_report_cn.pdf`
- Fixed-point contract: `docs/FIXED_POINT_CONTRACT.md`

## Key Result

Under the configured behavior-level stress case, the current RTL-equivalent calibration raises same-decision dynamic SNDR median from 36.214 dB to 92.007 dB after the diagnostic gain-aligned decode path. Gain-aligned weight RMSE improves from 147.9781 LSB to 0.1908 LSB.

This is behavior-level plus RTL simulation evidence. It is not AMS, transistor-level, PVT, PEX, or silicon signoff.

## Reproduction

From the repository root:

```powershell
python analysis\calibration_effectiveness_20260729\validate_current_calibration.py
python analysis\calibration_effectiveness_20260729\generate_report_assets.py
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run_all_xsim.ps1
```

To rebuild the report:

```powershell
cd analysis\calibration_effectiveness_20260729\report
xelatex -interaction=nonstopmode -halt-on-error current_calibration_validation_report_cn.tex
xelatex -interaction=nonstopmode -halt-on-error current_calibration_validation_report_cn.tex
xelatex -interaction=nonstopmode -halt-on-error current_calibration_validation_report_cn.tex
```
