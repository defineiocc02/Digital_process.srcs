# ============================================
# SAR ADC FPGA Bring-up Constraints
# ============================================

# -------- 全局安全默认 --------
set_property IOSTANDARD LVCMOS18 [get_ports *]
set_property DRIVE 4             [get_ports *]
set_property SLEW SLOW            [get_ports *]

# -------- 时钟 --------
set_property IOSTANDARD LVCMOS18 [get_ports clk]
set_property DRIVE 8             [get_ports clk]
set_property SLEW FAST            [get_ports clk]

create_clock -name sys_clk -period 20.000 [get_ports clk] ;# 50MHz

# -------- 输入防悬空 --------
set_property PULLDOWN true [get_ports {
    rst_n
    start_calib
    sar_ready
    conversion_done
}]
