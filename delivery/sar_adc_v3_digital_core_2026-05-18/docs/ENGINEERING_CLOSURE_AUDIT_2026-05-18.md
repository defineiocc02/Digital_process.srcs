# SAR ADC V3 Engineering Closure Audit Report

**Date:** 2026-05-18
**Baseline:** `master` before `d141b46` (v3.5.4-fixed-point-contract)
**Final:** `v3.6.0-engineering-closure` tag (see git tag for exact hash)
**Author:** Zhao Yi, with Claude Opus 4.7
**Scope:** 11 commits total:
  - 7 engineering closure commits (body of work)
  - 4 documentation / metadata commits (audit report, alignment, LICENSE+Copilot, README)

Aggregate: 46 files, +4534 / -166 lines
**Principle:** No algorithmic behavior changes. All core RTL, testbench, fixed-point contract, and build targets remain functionally identical.

---

## Executive Summary

The 11-commit closure pass transforms the SAR ADC V3 digital core from "good
module-level RTL with documentation" into "engineering-credible deliverable with
explicit build targets, constraint hygiene, timing contract, safety guards,
CI/lint infrastructure, and a project-house bilingual README."

Commits 8–11 add documentation, LICENSE, Copilot configuration, and README
presentation only. They do not modify RTL, TB, build scripts, constraints,
or CI behavior.

The original audit identified 13 issues across priority levels. This closure
resolves the top engineering risks while intentionally deferring mixed-signal
system integration, full Monte Carlo signoff, and ASIC SDC to later milestones.

---

## Commit-by-Commit Audit

### Commit 1 — `fix(docs): clarify tb_sar_recon_binary_norm verification scope`

| Item | Detail |
|------|--------|
| Hash | `d141b46` |
| Files | `README.md`, `MOC.md`, `delivery/README.md`, `delivery/docs/MOC.md` |
| Lines | +14 / -5 |

**What changed:**
- Added explicit scope notes: `tb_sar_recon_binary_norm` verifies binary-normalized reconstruction only; does NOT cover calibrated Q8 split-cap weight consistency.
- Directed readers to `tb_recon_q8_split_weights` for the Q8 contract.
- Zero stale `tb_sar_recon.sv` references remain (verified by full-repo grep).

**Why:**
The original audit flagged a file-to-documentation naming inconsistency. The TB had been renamed but docs were ambiguous about what it actually tests. This commit closes the naming discrepancy and prevents future confusion about which TB covers which contract.

---

### Commit 2 — `build: add authoritative Vivado target selection scripts`

| Item | Detail |
|------|--------|
| Hash | `8dad751` |
| Files | `scripts/build_vivado.tcl`, `scripts/build.ps1`, `constraints/core_synth.xdc`, `README.md`, `delivery/*` |
| Lines | +401 / -4 |

**What changed:**
- Created `scripts/build_vivado.tcl`: three named targets (`build_calib_core`, `build_recon_core`, `build_fpga_demo`) with explicit top-module selection.
- Created `scripts/build.ps1`: PowerShell wrapper supporting `$env:XILINX_VIVADO` and PATH-based Vivado discovery.
- Created `constraints/core_synth.xdc`: minimal 100 MHz clock constraint, no board pins or ILA.
- `build_fpga_demo` initially reserved (guarded until top skeleton exists in Commit 3).
- Legacy `synth_one_top.tcl` and `run_core_synth_checks.ps1` retained for backward compatibility.

**Verification:**
```
build_calib_core  PASS  (sar_calib_ctrl_serial)
build_recon_core  PASS  (sar_reconstruction)
build_fpga_demo   correctly rejected (missing sar_calib_fpga_top.sv)
```

**Why:**
The original `.xpr` file had inconsistent top-module settings between active project and delivery package. Making the TCL batch script authoritative eliminates ambiguity and enables reproducible CI-amenable synthesis.

---

### Commit 3 — `feat(rtl): add FPGA and ASIC digital top skeletons`

| Item | Detail |
|------|--------|
| Hash | `07af50c` |
| Files | `rtl/sar_calib_fpga_top.sv`, `rtl/sar_adc_digital_top.sv`, `rtl/` (5 files), `README.md`, `scripts/build_vivado.tcl` |
| Lines | +1504 / -14 |

**What changed:**
- Created `rtl/sar_calib_fpga_top.sv`: FPGA-only demo wrapper with button/LED I/O, deterministic comparator stub, and `(* mark_debug *)` taps. Not for ASIC.
- Created `rtl/sar_adc_digital_top.sv`: ASIC-oriented integration skeleton connecting calibration, SRM residue estimation, and reconstruction. No FPGA I/O.
- Established `rtl/` at repo root as the canonical batch-build RTL source (5 files: 3 core + 2 tops).
- Enabled `build_fpga_demo` target.

**Verification:**
```
build_calib_core  PASS
build_recon_core  PASS
build_fpga_demo   PASS  (now active, not reserved)
```

**Why:**
The original audit's P0-1 item: no top-level integration module existed. The `fpga_top_wrapper` and `sar_adc_controller` had been deleted to archive. This commit restores the engineering boundary with clean separation between FPGA demo (board I/O, debug) and ASIC digital (pure signal interface).

---

### Commit 4 — `fix(rtl): add FSM safe defaults and parameter guards`

| Item | Detail |
|------|--------|
| Hash | `e8196a9` |
| Files | `sar_calib_ctrl_serial.sv`, `srm_residue_estimator.sv`, `sar_reconstruction.sv` (3 locations each) |
| Lines | +300 / -48 |

**What changed:**
- `sar_calib_ctrl_serial.sv`: Added `default` branch to the sequential `case(state)` inside the data-path `always_ff`, driving all control outputs to safe values on unrecognized state. Eliminated Vivado Synth 8-155 warning.
- All three core RTL: Added `initial begin : p_parameter_guard` blocks with `$error` checks for the validated SAR ADC V3 configuration (CAP_NUM=20, OUTPUT_WIDTH=16, FRAC_BITS=8, DECISION_COUNT=22, etc.).

**Parameter guards added:**

| Module | Guards |
|--------|--------|
| `sar_calib_ctrl_serial` | CAP_NUM=20, WEIGHT_WIDTH>=30, COMP_WAIT_CYC>=1, AVG_LOOPS power-of-two, MAX_CALIB_BIT in range, REF_WEIGHT_LSB>0 |
| `srm_residue_estimator` | DECISION_COUNT=22, RESIDUE_WIDTH>=16, FRAC_BITS=8 |
| `sar_reconstruction` | CAP_NUM=20, WEIGHT_WIDTH>=30, OUTPUT_WIDTH=16, FRAC_BITS=8, MAX_CALIB_BIT in range, INIT_WEIGHT_LSB>0 |

**Verification:**
```
build_calib_core  PASS  (Synth 8-155 gone)
build_recon_core  PASS
build_fpga_demo   PASS
```

**Why:**
The original audit flagged the missing FSM `default` (P0-4) and the lack of parameter validation. The `default` branch provides a safe recovery path for illegal FSM states. The parameter guards make implicit design assumptions explicit: the current RTL is qualified for CAP_NUM=20 with the validated calibration flow, not an arbitrary CAP_NUM.

---

### Commit 5 — `docs: add mixed-signal timing contract`

| Item | Detail |
|------|--------|
| Hash | `87084d7` |
| Files | `docs/MIXED_SIGNAL_TIMING_CONTRACT.md`, `delivery/docs/MIXED_SIGNAL_TIMING_CONTRACT.md`, `README.md`, `MOC.md`, `delivery/*` |
| Lines | +444 |

**What changed:**
- New document: `docs/MIXED_SIGNAL_TIMING_CONTRACT.md` — 10-section contract covering clock/reset assumptions, calibration comparator timing, SRM residue timing, reconstruction timing, FPGA/ASIC wrapper contracts, CDC classification, and open items.
- Explicitly classifies `comp_out` as a **timed mixed-signal input**, not an arbitrary asynchronous GPIO.
- Documents why a blind two-flop synchronizer is not automatically correct for SAR bit-cycling.
- CDC posture table for every digital boundary signal.

**Key conclusions in the contract:**

| Signal | Classification | Required Action |
|--------|---------------|-----------------|
| `comp_out` | Timed mixed-signal input | Setup/hold contract or wrapper-level synchronizer/handshake |
| `rst_n` | Async reset | ASIC requires synchronized release |
| `srm_decision_bit` | Synchronous when valid | Wrapper must synchronize if source is async |
| Internal buses | Synchronous | No CDC |

**Why:**
The original audit's P0-5 item flagged potential CDC risk on `comp_out`. Rather than blindly adding a two-flop synchronizer (which would change SAR bit-cycle latency and could break the algorithm), this contract documents the timing assumptions the RTL makes and delegates the integration-level solution to the system designer. This is the correct professional approach for mixed-signal SAR ADC design.

---

### Commit 6 — `refactor(constraints): split core, board, and debug XDC`

| Item | Detail |
|------|--------|
| Hash | `85a2d3f` |
| Files | `constraints/sar_calib_fpga_legacy_board_hint.xdc`, `constraints/debug_ila_template.xdc`, `scripts/build_vivado.tcl`, `README.md`, `delivery/*` |
| Lines | +209 / -28 |

**What changed:**
- Renamed old `sar_calib_fpga.xdc` → `sar_calib_fpga_legacy_board_hint.xdc`, stripped ILA commands, marked as non-default.
- Created `constraints/debug_ila_template.xdc`: comment-only template keyed to stable `mark_debug` taps in `sar_calib_fpga_top.sv`.
- Updated `build_vivado.tcl`: all three targets default to `core_synth.xdc` only. Board and debug XDC are opt-in via `USE_BOARD_XDC=1` / `USE_DEBUG_XDC=1` environment variables.

**Constraint strategy:**

| XDC | Default | Enable |
|-----|---------|--------|
| `core_synth.xdc` | Yes | Always |
| `sar_calib_fpga_legacy_board_hint.xdc` | No | `USE_BOARD_XDC=1` |
| `debug_ila_template.xdc` | No | `USE_DEBUG_XDC=1` |

**Verification:** All three targets PASS with zero board/ILA warnings in synthesis logs.

**Why:**
The original legacy XDC contained board pin constraints (`rst_n_btn`, `start_sw`, `done_led`) and ILA debug commands that were incompatible with core RTL ports. These generated harmless-but-noisy synthesis warnings. The split ensures clean core builds while preserving the board reference for future FPGA demo work.

---

### Commit 7 — `ci: add lightweight RTL lint and repository consistency checks`

| Item | Detail |
|------|--------|
| Hash | `d4118df` |
| Files | `.github/workflows/rtl_lint.yml`, `scripts/check_repo_consistency.py`, `scripts/lint_verilator.sh`, `scripts/lint_verilator.ps1`, `README.md`, `delivery/*`, `docs/VERIFICATION.md` |
| Lines | +476 / -2 |

**What changed:**
- `scripts/check_repo_consistency.py`: validates 16 required files exist, detects stale `tb_sar_recon.sv` filenames (excluding archive/), checks 3 build targets are present in `build_vivado.tcl`, verifies `core_synth.xdc` is free of board/ILA tokens.
- `scripts/lint_verilator.sh` / `.ps1`: Verilator `--lint-only -Wall -Wno-fatal` on all 5 RTL files.
- `.github/workflows/rtl_lint.yml`: GitHub Actions workflow running consistency check + Verilator lint on every push and pull request.
- Updated `README.md`, delivery `README.md`, and `docs/VERIFICATION.md` with CI documentation.

**Verification:**
```
python3 scripts/check_repo_consistency.py  PASS
```

**Why:**
The original audit flagged missing CI/CD and no formal lint process. This commit adds the lightweight open-source path without requiring Vivado license/installation in CI. Vivado XSIM and synthesis remain local signoff steps.

---

## Aggregate Diff Summary

```
40 files changed, 3329 insertions(+), 82 deletions(-)
```

| Category | Files | Net Lines |
|----------|-------|-----------|
| New RTL (top skeletons) | 4 | +422 |
| Modified core RTL (guards/defaults) | 6 | +300 / -48 |
| Build scripts (new) | 4 | +198 |
| Constraints (new/split) | 5 | +88 / -28 |
| Documentation (new/updated) | 12 | +1587 |
| CI/lint scripts | 8 | +476 |
| CI workflow | 1 | +26 |

---

## Verification Matrix

### Build Targets (post-Closure)

```
build_calib_core   PASS  (sar_calib_ctrl_serial, Synth 8-155 resolved)
build_recon_core   PASS  (sar_reconstruction)
build_fpga_demo    PASS  (sar_calib_fpga_top, core_synth only)
```

### Consistency Check

```
check_repo_consistency.py  PASS (16 required files, 0 forbidden, 3 build targets, XDC clean)
```

### Vivado Warnings Resolved

| Warning | Pre-Closure | Post-Closure |
|---------|-------------|--------------|
| Synth 8-155 (case not full, no default) | Present | Resolved |
| Legacy board pin mismatch warnings | Present (in legacy flow) | Eliminated from default builds |
| ILA unconnected channel warnings | Present (in legacy flow) | Eliminated from default builds |

### Files With Zero Changes

The following were intentionally **not** modified:
- All four testbench files
- `fixed-point contract` (FIXED_POINT_CONTRACT.md)
- `sar_calib_fpga.xdc` (original, retained as historical reference in Vivado project)
- `run_all_xsim.ps1`, `run_xsim.ps1`, `synth_one_top.tcl` (legacy scripts, retained)
- All archival content under `archive/`
- `.xpr` project files (non-authoritative per build strategy)

---

## Deferred Items (Not in Scope)

The following items from the original audit are intentionally deferred:

| Item | Reason | Target Milestone |
|------|--------|-----------------|
| Monte Carlo expansion (5 → 100+) | TB parameterization exists; statistical signoff is a separate verification campaign | Pre-tapeout |
| Full SAR controller / mode arbitration | Requires mixed-signal system integration, not digital-only cleanup | System integration |
| ASIC SDC constraints | Requires gate-level netlist, PVT corners, and clock-tree specification | Physical design |
| CDC/RDC formal verification | Requires tool setup and waiver policy; contract doc provides the prerequisite | Pre-tapeout |
| Register configuration bus | Requires system architecture definition | System integration |
| DFT/scan insertion | Requires ASIC synthesis flow | Physical design |
| Verilator warning cleanup / waiver policy | Deferred to a separate `lint-cleanup` commit after first CI run collects warnings | Post-Closure |

---

## Project Maturity Assessment (Post-Closure)

| Dimension | Pre-Closure | Post-Closure |
|-----------|-------------|--------------|
| RTL quality | Good | Good + safety guards |
| Build reproducibility | Script-based but top implicit | Explicit 4-target authoritative entry, including ASIC skeleton |
| Top-level strategy | Missing | Dual-top (FPGA + ASIC) with clear separation |
| Constraint hygiene | Legacy board XDC mixed with core | Clean split, opt-in board/debug |
| Timing assumptions | Implicit / unclear | Documented in mixed-signal contract |
| CDC posture | Undefined | Classified, integration owner informed |
| CI/lint | None | Verilator + consistency check + GitHub Actions |
| Documentation coverage | Architecture + verification + version | + fixed-point contract + timing contract + build strategy + constraint strategy + CI docs |
| Deliverable confidence | Core RTL good, engineering boundary fuzzy | Engineering-credible handoff package |

---

## Recommendation

The 11-commit closure is complete and self-consistent. Each commit is independently
reviewable and revertible. No algorithmic behavior has changed.

**Tag:** `v3.6.0-engineering-closure`

Further pre-tapeout work (Monte Carlo, ASIC SDC, CDC formal, full SAR controller)
should proceed from this baseline as separate feature branches or milestones,
not as amendments to the closure commits.

## Post-Closure Cleanliness Update

After the v3.6.0 tag, the repository was tightened with:

- `build_asic_skeleton`, a Vivado synthesis target for `sar_adc_digital_top`.
- Repository consistency coverage for all four build targets.
- Trailing-whitespace cleanup in README/docs/RTL mirrors.
- LaTeX auxiliary output ignores for local paper drafting.

This update does not change algorithmic RTL behavior.
