# core_synth.xdc — Core-only synthesis timing constraint.
# Board-level pins and ILA debug constraints must NOT be placed here.
# For FPGA board/demo builds, source fpga_board_legacy.xdc and
# debug_ila.xdc separately.

create_clock -name clk -period 10.000 [get_ports clk]
