# Legacy FPGA board hint constraints.
#
# This file is NOT used by default core synthesis targets
# (build_calib_core, build_recon_core, build_fpga_demo).
#
# It may be used only when the selected top-level wrapper exposes matching
# board-level ports: clk, rst_n_btn, start_sw, done_led.
#
# This file is NOT an ASIC constraint file.
# This file is NOT a complete FPGA signoff constraint file.
# It is retained as a historical ACX720-V3 board reference only.
#
# Enable via:  $env:USE_BOARD_XDC = "1"
#              .\scripts\build.ps1 -Target build_fpga_demo

## =========================================================
## 1. Timing constraint
## =========================================================
create_clock -period 20.000 -name sys_clk_pin [get_ports clk]

## =========================================================
## 2. Pin constraints (ACX720-V3 board manual reference)
## =========================================================

# --- Clock CLK (manual P29 table 6: FPGA_GCLK1 -> Y18) ---
set_property PACKAGE_PIN Y18 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]

# --- Reset button (manual P26 table 3: S0 -> F15) ---
set_property PACKAGE_PIN F15 [get_ports rst_n_btn]
set_property IOSTANDARD LVCMOS33 [get_ports rst_n_btn]

# --- Start switch (manual P27 table 4: SW0 -> G22) ---
set_property PACKAGE_PIN G22 [get_ports start_sw]
set_property IOSTANDARD LVCMOS33 [get_ports start_sw]

# --- Done LED (manual P28 table 5: LED0 -> M22) ---
set_property PACKAGE_PIN M22 [get_ports done_led]
set_property IOSTANDARD LVCMOS33 [get_ports done_led]

## =========================================================
## 3. Configuration
## =========================================================
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
