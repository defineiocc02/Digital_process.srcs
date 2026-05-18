# SAR ADC V3 Digital Core Delivery Package

Frozen date: 2026-05-18

This package is a handoff snapshot of the verified minimal digital core. It
contains the active RTL, production-style testbenches, maintenance documents,
and repeatable Vivado batch scripts.

## Contents

| Directory | Contents |
| --- | --- |
| `rtl/` | Three active synthesizable SystemVerilog RTL cores |
| `tb/` | Three active XSIM testbenches |
| `docs/` | Version, architecture, verification, reproduction, and signoff review docs |
| `scripts/` | XSIM and synthesis batch scripts |
| `constraints/` | Legacy board XDC hint, not final signoff constraints |
| `vivado/` | Reference `.xpr` only; source files in this package are the authority |

## Status

- XSIM: PASS for all three testbenches.
- Synthesis: PASS for all three RTL tops on `xc7a35tfgg484-2`.
- ASIC: RTL prototype only; see `docs/FPGA_ASIC_SIGNOFF_REVIEW_2026-05-18.md`.
- Detailed Chinese final report:
  `docs/FINAL_REPRODUCTION_AND_VERIFICATION_REPORT_CN_2026-05-18.md`.

## Important Limit

This is a core delivery package, not a complete board bitstream or ASIC tapeout
database. Final integration still needs wrapper, I/O constraints, analog
boundary timing, CDC/RDC review, and implementation signoff.
