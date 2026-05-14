`timescale 1ns/1ps

module fpga_top_wrapper (
    input  wire clk,           // System clock (e.g. 100MHz or 50MHz)
    input  wire rst_n_btn,     // Reset button
    input  wire start_sw,      // Start switch
    output wire done_led       // Done indicator LED
);

// --- Internal Signals ---
    logic comp_out;
    logic [19:0] dac_p_force;
    logic [19:0] dac_n_force;
    logic calib_mode_en;

    // =======================================================
    // [Critical Modification] Added (* mark_debug = "true" *) attribute
    // This forces synthesis to preserve these signals for ILA debugging
    // =======================================================
    (* mark_debug = "true" *) logic w_wr_en;
    (* mark_debug = "true" *) logic [4:0] w_wr_addr;
    (* mark_debug = "true" *) logic signed [29:0] w_wr_data;

    // --- 1. Instantiate Calibration Core (DUT) ---
    sar_calib_ctrl_serial #(
        .CAP_NUM(20),
        .WEIGHT_WIDTH(30),
        .AVG_LOOPS(32)   // FPGA resources sufficient, can use 32 or 64
    ) u_core (
        .clk           (clk),
        .rst_n         (rst_n_btn),    // Actual button needs Debounce (omitted)
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

    // --- 2. Instantiate Virtual ADC Physical Model ---
    virtual_adc_phy #(
        .CAP_NUM(20)
    ) u_phy_model (
        .clk         (clk),
        .rst_n       (rst_n_btn),
        .dac_p_force (dac_p_force),
        .dac_n_force (dac_n_force),
        .comp_out    (comp_out)
    );

    // --- 3. (Optional) ILA Debug Core Instantiation ---
    // Uncomment to add ILA IP in Vivado for hardware debugging
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
