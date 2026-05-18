#!/usr/bin/env python3
"""Repository consistency check for SAR ADC V3 digital core.

Catches structural regressions: missing files, stale legacy filenames,
missing build targets, and constraint contamination in core_synth.xdc.
"""

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]

RTL_DIR = ROOT / "rtl"
TB_DIR = ROOT / "Digital_process" / "Digital_process.srcs" / "sim_1" / "new"
CONSTR_DIR = ROOT / "constraints"
DOCS_DIR = ROOT / "docs"

REQUIRED_FILES = [
    # RTL
    RTL_DIR / "sar_calib_ctrl_serial.sv",
    RTL_DIR / "sar_reconstruction.sv",
    RTL_DIR / "srm_residue_estimator.sv",
    RTL_DIR / "sar_calib_fpga_top.sv",
    RTL_DIR / "sar_adc_digital_top.sv",
    # TB
    TB_DIR / "tb_sar_recon_binary_norm.sv",
    TB_DIR / "tb_recon_q8_split_weights.sv",
    TB_DIR / "tb_gain_comp_check_lsb.sv",
    TB_DIR / "tb_srm_residue_estimator.sv",
    # Constraints
    CONSTR_DIR / "core_synth.xdc",
    CONSTR_DIR / "sar_calib_fpga_legacy_board_hint.xdc",
    CONSTR_DIR / "debug_ila_template.xdc",
    # Contracts
    DOCS_DIR / "FIXED_POINT_CONTRACT.md",
    DOCS_DIR / "MIXED_SIGNAL_TIMING_CONTRACT.md",
    # Scripts
    ROOT / "scripts" / "build_vivado.tcl",
    ROOT / "scripts" / "build.ps1",
]

FORBIDDEN_EXACT_FILENAMES = [
    "tb_sar_recon.sv",
]

REQUIRED_BUILD_TARGETS = [
    "build_calib_core",
    "build_recon_core",
    "build_fpga_demo",
]

CORE_XDC = CONSTR_DIR / "core_synth.xdc"
FORBIDDEN_CORE_XDC_TOKENS = ["PACKAGE_PIN", "create_debug_core", "connect_debug_port"]


def fail(msg: str) -> None:
    print(f"ERROR: {msg}")
    sys.exit(1)


def main() -> None:
    print("== SAR ADC V3 repository consistency check ==")

    errors = 0

    for path in REQUIRED_FILES:
        if not path.exists():
            print(f"  MISSING: {path.relative_to(ROOT)}")
            errors += 1
        else:
            print(f"  OK: {path.relative_to(ROOT)}")

    # Forbidden legacy filenames — must not appear in active source trees.
    # Archived copies under archive/ are exempt.
    for forbidden in FORBIDDEN_EXACT_FILENAMES:
        hits = list(ROOT.rglob(forbidden))
        for h in hits:
            rel = h.relative_to(ROOT)
            if rel.parts and rel.parts[0] == "archive":
                continue
            print(f"  FORBIDDEN: {rel}")
            errors += 1

    # Build target presence in build_vivado.tcl
    build_tcl = ROOT / "scripts" / "build_vivado.tcl"
    if build_tcl.exists():
        text = build_tcl.read_text(encoding="utf-8", errors="ignore")
        for target in REQUIRED_BUILD_TARGETS:
            if target in text:
                print(f"  OK: build target '{target}' found in build_vivado.tcl")
            else:
                print(f"  MISSING: build target '{target}' not found in build_vivado.tcl")
                errors += 1

    # Core XDC must not contain board or debug commands
    if CORE_XDC.exists():
        text = CORE_XDC.read_text(encoding="utf-8", errors="ignore")
        for token in FORBIDDEN_CORE_XDC_TOKENS:
            if token in text:
                print(f"  FAIL: core_synth.xdc contains forbidden token: {token}")
                errors += 1
            else:
                print(f"  OK: core_synth.xdc clean of '{token}'")

    if errors:
        fail(f"{errors} consistency error(s)")
    print("PASS: repository consistency check completed")


if __name__ == "__main__":
    main()
