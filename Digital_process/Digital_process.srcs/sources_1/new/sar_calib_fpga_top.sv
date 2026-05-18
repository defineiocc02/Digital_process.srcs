// =============================================================================
// File Name   : sar_calib_fpga_top.sv
// Module Name : sar_calib_fpga_top
// Description : Minimal FPGA demo wrapper for SAR calibration controller.
//
// Scope:
//   - This wrapper is for FPGA build/demo only.
//   - It is NOT the ASIC digital top.
//   - It intentionally does not implement the full SAR ADC mixed-signal system.
//   - Comparator input is currently tied to a deterministic stub.
//   - ILA IP is not instantiated here; debug taps are marked for later use.
//
// Build Target:
//   build_fpga_demo
// =============================================================================

`timescale 1ns / 1ps

module sar_calib_fpga_top #(
    parameter int CAP_NUM        = 20,
    parameter int WEIGHT_WIDTH   = 30,
    parameter int COMP_WAIT_CYC  = 16,
    parameter int AVG_LOOPS      = 32,
    parameter int MAX_CALIB_BIT  = 5,
    parameter int REF_WEIGHT_LSB = 256
) (
    input  logic clk,
    input  logic rst_n_btn,
    input  logic start_sw,
    output logic done_led
);

    // -------------------------------------------------------------------------
    // Reset and start pulse handling
    // -------------------------------------------------------------------------
    logic       rst_n;
    logic       start_sw_d;
    logic       start_calib;

    assign rst_n = rst_n_btn;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            start_sw_d <= 1'b0;
        end else begin
            start_sw_d <= start_sw;
        end
    end

    assign start_calib = start_sw & ~start_sw_d;

    // -------------------------------------------------------------------------
    // Calibration controller wires
    // -------------------------------------------------------------------------
    logic calib_done;
    logic calib_mode_en;

    logic                   comp_out_stub;
    logic [CAP_NUM-1:0]     dac_p_force;
    logic [CAP_NUM-1:0]     dac_n_force;
    logic                   w_wr_en;
    logic [4:0]             w_wr_addr;
    logic signed [WEIGHT_WIDTH-1:0] w_wr_data;

    // Deterministic placeholder until an AFE/comparator model is connected.
    // This is sufficient for synthesis/build closure, not algorithm validation.
    assign comp_out_stub = 1'b0;

    sar_calib_ctrl_serial #(
        .CAP_NUM        (CAP_NUM),
        .WEIGHT_WIDTH   (WEIGHT_WIDTH),
        .COMP_WAIT_CYC  (COMP_WAIT_CYC),
        .AVG_LOOPS      (AVG_LOOPS),
        .MAX_CALIB_BIT  (MAX_CALIB_BIT),
        .REF_WEIGHT_LSB (REF_WEIGHT_LSB)
    ) u_calib_ctrl (
        .clk          (clk),
        .rst_n        (rst_n),
        .start_calib  (start_calib),
        .calib_done   (calib_done),
        .calib_mode_en(calib_mode_en),
        .comp_out     (comp_out_stub),
        .dac_p_force  (dac_p_force),
        .dac_n_force  (dac_n_force),
        .w_wr_en      (w_wr_en),
        .w_wr_addr    (w_wr_addr),
        .w_wr_data    (w_wr_data)
    );

    assign done_led = calib_done;

    // -------------------------------------------------------------------------
    // Debug taps for future ILA connection.
    // No ILA core is instantiated in this commit.
    // -------------------------------------------------------------------------
    (* mark_debug = "true" *) logic                          dbg_calib_done;
    (* mark_debug = "true" *) logic                          dbg_calib_mode_en;
    (* mark_debug = "true" *) logic                          dbg_w_wr_en;
    (* mark_debug = "true" *) logic [4:0]                    dbg_w_wr_addr;
    (* mark_debug = "true" *) logic signed [WEIGHT_WIDTH-1:0] dbg_w_wr_data;

    always_comb begin
        dbg_calib_done    = calib_done;
        dbg_calib_mode_en = calib_mode_en;
        dbg_w_wr_en       = w_wr_en;
        dbg_w_wr_addr     = w_wr_addr;
        dbg_w_wr_data     = w_wr_data;
    end

endmodule
