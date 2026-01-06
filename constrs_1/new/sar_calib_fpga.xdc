## =========================================================
## 1. 时序约束
## =========================================================
create_clock -period 20.000 -name sys_clk_pin [get_ports clk]

## =========================================================
## 2. 管脚约束 (根据 ACX720-V3 手册确认)
## =========================================================

# --- 时钟 CLK (手册 P29 表6: FPGA_GCLK1 -> Y18) ---
set_property PACKAGE_PIN Y18 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]

# --- 复位按键 (手册 P26 表3: S0 -> F15) ---
set_property PACKAGE_PIN F15 [get_ports rst_n_btn]
set_property IOSTANDARD LVCMOS33 [get_ports rst_n_btn]

# --- 启动开关 (手册 P27 表4: SW0 -> G22) ---
set_property PACKAGE_PIN G22 [get_ports start_sw]
set_property IOSTANDARD LVCMOS33 [get_ports start_sw]

# --- 完成 LED (手册 P28 表5: LED0 -> M22) ---
set_property PACKAGE_PIN M22 [get_ports done_led]
set_property IOSTANDARD LVCMOS33 [get_ports done_led]

## =========================================================
## 3. 配置
## =========================================================
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

create_debug_core u_ila_0 ila
set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_0]
set_property ALL_PROBE_SAME_MU_CNT 1 [get_debug_cores u_ila_0]
set_property C_ADV_TRIGGER false [get_debug_cores u_ila_0]
set_property C_DATA_DEPTH 1024 [get_debug_cores u_ila_0]
set_property C_EN_STRG_QUAL false [get_debug_cores u_ila_0]
set_property C_INPUT_PIPE_STAGES 0 [get_debug_cores u_ila_0]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_0]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_0]
set_property port_width 1 [get_debug_ports u_ila_0/clk]
connect_debug_port u_ila_0/clk [get_nets [list clk_IBUF_BUFG]]
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe0]
set_property port_width 30 [get_debug_ports u_ila_0/probe0]
connect_debug_port u_ila_0/probe0 [get_nets [list {w_wr_data[0]} {w_wr_data[1]} {w_wr_data[2]} {w_wr_data[3]} {w_wr_data[4]} {w_wr_data[5]} {w_wr_data[6]} {w_wr_data[7]} {w_wr_data[8]} {w_wr_data[9]} {w_wr_data[10]} {w_wr_data[11]} {w_wr_data[12]} {w_wr_data[13]} {w_wr_data[14]} {w_wr_data[15]} {w_wr_data[16]} {w_wr_data[17]} {w_wr_data[18]} {w_wr_data[19]} {w_wr_data[20]} {w_wr_data[21]} {w_wr_data[22]} {w_wr_data[23]} {w_wr_data[24]} {w_wr_data[25]} {w_wr_data[26]} {w_wr_data[27]} {w_wr_data[28]} {w_wr_data[29]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe1]
set_property port_width 5 [get_debug_ports u_ila_0/probe1]
connect_debug_port u_ila_0/probe1 [get_nets [list {w_wr_addr[0]} {w_wr_addr[1]} {w_wr_addr[2]} {w_wr_addr[3]} {w_wr_addr[4]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe2]
set_property port_width 1 [get_debug_ports u_ila_0/probe2]
connect_debug_port u_ila_0/probe2 [get_nets [list w_wr_en]]
set_property C_CLK_INPUT_FREQ_HZ 300000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets clk_IBUF_BUFG]
