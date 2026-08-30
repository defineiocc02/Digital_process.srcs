# SAR16B Full-Flow Independent Review

This folder contains a four-pass independent review of the maintained SAR ADC
digital calibration/reconstruction project against the live VM `SAR_16B_5M`
circuit family.

Review ownership:

- `reviews/REVIEW_01_RTL_TO_NETLIST_CN.md`: RTL, DV, CDC, synthesis, STA, DFT.
- `reviews/REVIEW_02_AMS_LAYOUT_GDS_CN.md`: AMS, schematic, layout, PEX, physical signoff, GDS.
- `reviews/REVIEW_03_SILICON_PAPER_NOVELTY_CN.md`: package, ATE/lab test, paper comparison, novelty candidates.
- `reviews/REVIEW_04_ADVERSARIAL_INTEGRATION_CN.md`: independent cross-domain challenge review.
- `SAR16B_RTL_TO_SILICON_MASTER_REVIEW_CN.md`: integrated final report maintained by the parent reviewer.
- `../self_cal_adctoolbox_behavioral_20260830/`: noise-isolated 16-bit on-chip
  self-calibration experiment, ADCToolbox audit, tests, data, and figures.

Evidence policy:

- `verified`: directly supported by repository, live VM, simulator, report, or paper evidence.
- `partial`: some evidence exists but the flow cannot be independently closed.
- `gap`: a required deliverable or result is absent.
- `not_checked`: outside the available inspection boundary.

No review may infer successful GDS signoff, tapeout readiness, or silicon
performance from an RTL unit test or a schematic-only simulation.
