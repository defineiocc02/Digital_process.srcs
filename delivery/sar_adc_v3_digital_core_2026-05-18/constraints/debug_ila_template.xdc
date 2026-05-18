# Debug ILA template.
#
# This file is intentionally NOT read by default.
# Enable it only after the FPGA wrapper and debug nets are stable.
#
# Enable via:  $env:USE_DEBUG_XDC = "1"
#              .\scripts\build.ps1 -Target build_fpga_demo
#
# Expected debug tap names are declared in sar_calib_fpga_top.sv with
# (* mark_debug = "true" *):
#
#   dbg_calib_done
#   dbg_calib_mode_en
#   dbg_w_wr_en
#   dbg_w_wr_addr[4:0]
#   dbg_w_wr_data[29:0]
#
# --- Example ILA instantiation (not active) ---
#
# To create a live ILA core, uncomment and adapt the following pattern:
#
#   create_debug_core u_ila_0 ila
#   set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_0]
#   set_property C_DATA_DEPTH 1024 [get_debug_cores u_ila_0]
#   set_property port_width 1 [get_debug_ports u_ila_0/clk]
#   connect_debug_port u_ila_0/clk [get_nets -hierarchical *clk*]
#
#   create_debug_port u_ila_0 probe
#   set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe0]
#   set_property port_width 30 [get_debug_ports u_ila_0/probe0]
#   connect_debug_port u_ila_0/probe0 [get_nets -hierarchical *dbg_w_wr_data*]
#
# Do NOT directly probe optimized internal nets such as w_wr_data[0].
# Use the explicit mark_debug tap signals from sar_calib_fpga_top instead.
#
# The ILA clock input frequency must be configured:
#   set_property C_CLK_INPUT_FREQ_HZ 300000000 [get_debug_cores dbg_hub]
