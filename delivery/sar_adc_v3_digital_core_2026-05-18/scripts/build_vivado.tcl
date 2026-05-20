# SAR ADC V3 — Authoritative Vivado batch build entry.
# Select the synthesis top via the BUILD_TARGET environment variable.
# Do NOT rely on .xpr top-module settings; they are not authoritative.

if {![info exists ::env(BUILD_TARGET)]} {
    puts "ERROR: BUILD_TARGET is not set."
    puts "Valid targets:"
    puts "  build_calib_core"
    puts "  build_recon_core"
    puts "  build_fpga_demo"
    puts "  build_asic_skeleton"
    exit 1
}

set BUILD_TARGET $::env(BUILD_TARGET)
set PART        "xc7a35tfgg484-2"

# ----------------------------------------------------------------------
# Resolve repo root and RTL / constraints directories
# ----------------------------------------------------------------------
set SCRIPT_DIR  [file dirname [info script]]
set ROOT_DIR    [file normalize [file join $SCRIPT_DIR ".."]]

# Auto-detect RTL layout:
#   1) repo-root rtl/ (delivery-package layout)
#   2) Vivado project sources_1/new/  (active-project layout)
if {[file exists [file join $ROOT_DIR "rtl"]]} {
    set RTL_DIR [file join $ROOT_DIR "rtl"]
} else {
    set RTL_DIR [file join $ROOT_DIR "Digital_process" "Digital_process.srcs" "sources_1" "new"]
}

set CONSTR_DIR [file join $ROOT_DIR "constraints"]

# ----------------------------------------------------------------------
# Select top and constraints by target
# ----------------------------------------------------------------------
switch -- $BUILD_TARGET {
    "build_calib_core" {
        set TOP      "sar_calib_ctrl_serial"
        set XDC_LIST [list [file join $CONSTR_DIR "core_synth.xdc"]]
    }
    "build_recon_core" {
        set TOP      "sar_reconstruction"
        set XDC_LIST [list [file join $CONSTR_DIR "core_synth.xdc"]]
    }
    "build_fpga_demo" {
        set TOP      "sar_calib_fpga_top"
        set XDC_LIST [list \
            [file join $CONSTR_DIR "core_synth.xdc"] \
        ]

        if {![file exists [file join $RTL_DIR "sar_calib_fpga_top.sv"]]} {
            puts "ERROR: build_fpga_demo requires sar_calib_fpga_top.sv."
            puts "This target is reserved until the FPGA top skeleton is added."
            exit 1
        }
    }
    "build_asic_skeleton" {
        set TOP      "sar_adc_digital_top"
        set XDC_LIST [list [file join $CONSTR_DIR "core_synth.xdc"]]

        if {![file exists [file join $RTL_DIR "sar_adc_digital_top.sv"]]} {
            puts "ERROR: build_asic_skeleton requires sar_adc_digital_top.sv."
            exit 1
        }
    }
    default {
        puts "ERROR: Unknown BUILD_TARGET = '$BUILD_TARGET'"
        puts "Valid targets:"
        puts "  build_calib_core"
        puts "  build_recon_core"
        puts "  build_fpga_demo"
        puts "  build_asic_skeleton"
        exit 1
    }
}

puts "INFO: BUILD_TARGET = $BUILD_TARGET"
puts "INFO: TOP          = $TOP"
puts "INFO: PART         = $PART"
puts "INFO: RTL_DIR      = $RTL_DIR"

# ----------------------------------------------------------------------
# Optional XDC: board and debug constraints are opt-in only.
# Core builds must not read board-level or ILA constraints by default.
# ----------------------------------------------------------------------
set BOARD_XDC [file join $CONSTR_DIR "sar_calib_fpga_legacy_board_hint.xdc"]
set DEBUG_XDC [file join $CONSTR_DIR "debug_ila_template.xdc"]

if {[info exists ::env(USE_BOARD_XDC)] && $::env(USE_BOARD_XDC) eq "1"} {
    if {[file exists $BOARD_XDC]} {
        puts "INFO: opt-in board XDC  $BOARD_XDC"
        lappend XDC_LIST $BOARD_XDC
    } else {
        puts "WARNING: USE_BOARD_XDC=1 but board XDC not found: $BOARD_XDC"
    }
}

if {[info exists ::env(USE_DEBUG_XDC)] && $::env(USE_DEBUG_XDC) eq "1"} {
    if {[file exists $DEBUG_XDC]} {
        puts "INFO: opt-in debug XDC  $DEBUG_XDC"
        lappend XDC_LIST $DEBUG_XDC
    } else {
        puts "WARNING: USE_DEBUG_XDC=1 but debug XDC not found: $DEBUG_XDC"
    }
}

# ----------------------------------------------------------------------
# Create in-memory project (must precede read_verilog / read_xdc)
# ----------------------------------------------------------------------
create_project -in_memory -part $PART

# ----------------------------------------------------------------------
# Read core RTL
# ----------------------------------------------------------------------
set CORE_RTL [list \
    "sar_calib_ctrl_serial.sv" \
    "sar_reconstruction.sv" \
    "srm_residue_estimator.sv" \
]

foreach rtl_file $CORE_RTL {
    set abs_path [file join $RTL_DIR $rtl_file]
    if {![file exists $abs_path]} {
        puts "ERROR: RTL file not found: $abs_path"
        exit 2
    }
    read_verilog -sv $abs_path
}

# Optional FPGA top wrapper
if {$BUILD_TARGET eq "build_fpga_demo"} {
    set fpga_top [file join $RTL_DIR "sar_calib_fpga_top.sv"]
    if {[file exists $fpga_top]} {
        read_verilog -sv $fpga_top
    }
}

# Optional ASIC-oriented integration skeleton
if {$BUILD_TARGET eq "build_asic_skeleton"} {
    set asic_top [file join $RTL_DIR "sar_adc_digital_top.sv"]
    if {[file exists $asic_top]} {
        read_verilog -sv $asic_top
    }
}

# ----------------------------------------------------------------------
# Constraints
# ----------------------------------------------------------------------
foreach xdc $XDC_LIST {
    if {[file exists $xdc]} {
        puts "INFO: reading XDC   $xdc"
        read_xdc $xdc
    } else {
        puts "WARNING: XDC not found, skipped: $xdc"
    }
}

# ----------------------------------------------------------------------
# Synthesis
# ----------------------------------------------------------------------
synth_design -top $TOP -part $PART -flatten_hierarchy rebuilt

# ----------------------------------------------------------------------
# Reports
# ----------------------------------------------------------------------
set OUT_DIR [file join $ROOT_DIR "sim_work" "synth" $BUILD_TARGET]
file mkdir $OUT_DIR

report_utilization  -file [file join $OUT_DIR "${BUILD_TARGET}_utilization.rpt"]
report_timing_summary -delay_type max -max_paths 10 \
    -file [file join $OUT_DIR "${BUILD_TARGET}_timing_summary.rpt"]
check_timing -file [file join $OUT_DIR "${BUILD_TARGET}_check_timing.rpt"]
write_checkpoint -force [file join $OUT_DIR "${BUILD_TARGET}.dcp"]

puts "BUILD PASS target=$BUILD_TARGET top=$TOP part=$PART"
