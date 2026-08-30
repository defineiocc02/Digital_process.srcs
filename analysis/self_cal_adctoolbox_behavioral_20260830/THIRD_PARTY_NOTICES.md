# Third-Party Notices

## ADCToolbox

- Project: ADCToolbox
- Authors: Zhishuai Zhang and Lu Jie
- Upstream: <https://github.com/Arcadia-1/ADCToolbox>
- Reviewed version: `0.9.1`
- Reviewed commit: `a8995cf4faf73dde9918589bfeb866c6a77db12d`
- License: MIT

This experiment uses ADCToolbox for standardized spectrum analysis,
ramp-histogram DNL/INL extraction, calibration-matrix diagnostics, and one
explicit external sine-fit comparison baseline.

The project's 16-bit on-chip foreground self-calibration algorithm is not
copied from ADCToolbox. Its source of truth remains the local RTL and the
RTL-equivalent behavioral mirror in:

```text
analysis/full_sar_behavioral_20260729/full_sar_model.py
```

The reviewed license text is present in the audited checkout at:

```text
C:\Users\Administrator\Desktop\ADCToolbox_EVAL_20260728\upstream\LICENSE
```
