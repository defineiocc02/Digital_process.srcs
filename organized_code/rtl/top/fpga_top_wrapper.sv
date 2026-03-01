`timescale 1ns/1ps

module fpga_top_wrapper (
    input  wire clk,           // 板载时钟 (e.g. 100MHz or 50MHz)
    input  wire rst_n_btn,     // 复位按键
    input  wire start_sw,      // 启动开关
    output wire done_led       // 完成指示灯
);

// --- 内部信号 ---
    logic comp_out;
    logic [19:0] dac_p_force;
    logic [19:0] dac_n_force;
    logic calib_mode_en;

    // =======================================================
    // [关键修改] 添加 (* mark_debug = "true" *) 属性
    // 这能强制综合器保留计算逻辑，解决 "55 LUTs" 问题
    // =======================================================
    (* mark_debug = "true" *) logic w_wr_en;
    (* mark_debug = "true" *) logic [4:0] w_wr_addr;
    (* mark_debug = "true" *) logic signed [29:0] w_wr_data;

    // --- 1. 实例化核心控制器 (DUT) ---
    sar_calib_ctrl_serial #(
        .CAP_NUM(20),
        .WEIGHT_WIDTH(30),
        .AVG_LOOPS(32)   // FPGA 上跑快点，可以用 32 或 64
    ) u_core (
        .clk           (clk),
        .rst_n         (rst_n_btn),    // 实际工程建议加 Debounce (消抖)
        .start_calib   (start_sw),
        .calib_done    (done_led),
        .calib_mode_en (calib_mode_en),
        .comp_out      (comp_out),
        .dac_p_force   (dac_p_force),
        .dac_n_force   (dac_n_force),
        .w_wr_en       (w_wr_en),
        .w_wr_addr     (w_wr_addr),
        .w_wr_data     (w_wr_data)
    );

    // --- 2. 实例化虚拟 ADC 物理模型 ---
    virtual_adc_phy #(
        .CAP_NUM(20)
    ) u_phy_model (
        .clk         (clk),
        .rst_n       (rst_n_btn),
        .dac_p_force (dac_p_force),
        .dac_n_force (dac_n_force),
        .comp_out    (comp_out)
    );

    // --- 3. (可选) ILA 调试核实例化 ---
    // 如果您想在 Vivado 里看到波形，请取消注释并生成 IP
    /*
    ila_0 u_ila (
        .clk(clk), 
        .probe0(dac_p_force),  // [19:0]
        .probe1(comp_out),     // [0:0]
        .probe2(w_wr_en),      // [0:0]
        .probe3(w_wr_addr),    // [4:0]
        .probe4(w_wr_data),    // [29:0]
        .probe5(done_led)      // [0:0]
    );
    */

endmodule