# SAR ADC V3 Digital Core Delivery Package

Frozen date: 2026-05-18

This package is a handoff snapshot of the verified minimal digital core. It
contains the active RTL, production-style testbenches, maintenance documents,
and repeatable Vivado batch scripts.

## Contents

| Directory | Contents |
| --- | --- |
| `rtl/` | Three active synthesizable SystemVerilog RTL cores |
| `tb/` | Four active XSIM testbenches with industrial-style English comments |
| `docs/` | Version, architecture, verification, reproduction, and signoff review docs |
| `scripts/` | XSIM and synthesis batch scripts |
| `constraints/` | Legacy board XDC hint, not final signoff constraints |
| `vivado/` | Reference `.xpr` only; source files in this package are the authority |

## Authoritative Build Targets

The Vivado `.xpr` file is **not** the authoritative build source.  
Use the batch scripts under `scripts/` to select the intended synthesis top.

| Target | Top Module | Purpose |
|---|---|---|
| `build_calib_core` | `sar_calib_ctrl_serial` | Standalone calibration controller synthesis |
| `build_recon_core` | `sar_reconstruction` | Standalone reconstruction datapath synthesis |
| `build_fpga_demo` | `sar_calib_fpga_top` | FPGA board/demo top, reserved until the FPGA wrapper is added |

```powershell
.\scripts\build.ps1 -Target build_calib_core
.\scripts\build.ps1 -Target build_recon_core
```

`build_fpga_demo` is intentionally guarded until `sar_calib_fpga_top.sv` exists.

## Status

- XSIM: PASS for all four testbenches.
- Synthesis: PASS for all three RTL tops on `xc7a35tfgg484-2`.
- ASIC: RTL prototype only; see `docs/FPGA_ASIC_SIGNOFF_REVIEW_2026-05-18.md`.
- TB maintenance: see `docs/TB_INDUSTRIAL_VERIFICATION_GUIDE.md`.
- Fixed-point contract: see `docs/FIXED_POINT_CONTRACT.md`.
- Technical gap analysis: see
  `docs/TECHNICAL_ALGORITHM_GAP_ANALYSIS_CN_2026-05-18.md`.
- Detailed Chinese final report:
  `docs/FINAL_REPRODUCTION_AND_VERIFICATION_REPORT_CN_2026-05-18.md`.

## Important Limit

This is a core delivery package, not a complete board bitstream or ASIC tapeout
database. Final integration still needs wrapper, I/O constraints, analog
boundary timing, CDC/RDC review, and implementation signoff.

### TB Scope Note

`tb/tb_sar_recon_binary_norm.sv` verifies binary-normalized 20-bit raw-code to
signed 16-bit reconstruction only. It does **not** verify calibrated Q8
split-cap weight consistency; use `tb/tb_recon_q8_split_weights.sv` for that.
