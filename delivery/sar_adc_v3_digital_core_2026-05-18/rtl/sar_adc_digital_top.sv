// =============================================================================
// File Name   : sar_adc_digital_top.sv
// Module Name : sar_adc_digital_top
// Description : ASIC-oriented digital integration skeleton for SAR ADC V3.
//
// Scope:
//   - This is the ASIC digital top skeleton.
//   - It connects calibration, SRM residue estimation, and reconstruction.
//   - It does NOT include FPGA board IO, buttons, LEDs, or ILA.
//   - It does NOT yet implement the full SAR controller or mode arbitration.
//   - Mixed-signal timing assumptions are documented separately.
//
// Build Role:
//   Future ASIC digital synthesis top after interface contract closure.
// =============================================================================

`timescale 1ns / 1ps

module sar_adc_digital_top #(
    parameter int CAP_NUM         = 20,
    parameter int WEIGHT_WIDTH    = 30,
    parameter int OUTPUT_WIDTH    = 16,
    parameter int FRAC_BITS       = 8,
    parameter int COMP_WAIT_CYC   = 16,
    parameter int AVG_LOOPS       = 32,
    parameter int MAX_CALIB_BIT   = 5,
    parameter int REF_WEIGHT_LSB  = 256,
    parameter int SRM_DECISIONS   = 22
) (
    // -------------------------------------------------------------------------
    // Global
    // -------------------------------------------------------------------------
    input  logic clk,
    input  logic rst_n,

    // -------------------------------------------------------------------------
    // Calibration control
    // -------------------------------------------------------------------------
    input  logic start_calib,
    input  logic calib_comp_out,

    output logic calib_done,
    output logic calib_mode_en,
    output logic [CAP_NUM-1:0] dac_p_force,
    output logic [CAP_NUM-1:0] dac_n_force,

    // -------------------------------------------------------------------------
    // Normal SAR reconstruction input
    // -------------------------------------------------------------------------
    input  logic data_valid_in,
    input  logic [CAP_NUM-1:0] raw_bits,

    // -------------------------------------------------------------------------
    // SRM residue acquisition input
    // -------------------------------------------------------------------------
    input  logic srm_start,
    input  logic srm_decision_valid,
    input  logic srm_decision_bit,

    output logic srm_busy,
    output logic srm_done,
    output logic [4:0] srm_decision_index,
    output logic [4:0] srm_ones_count,

    // -------------------------------------------------------------------------
    // Final ADC output
    // -------------------------------------------------------------------------
    output logic signed [OUTPUT_WIDTH-1:0] adc_dout,
    output logic data_valid_out
);

    // -------------------------------------------------------------------------
    // Calibration weight write-back bus
    // -------------------------------------------------------------------------
    logic                          w_wr_en;
    logic [4:0]                    w_wr_addr;
    logic signed [WEIGHT_WIDTH-1:0] w_wr_data;

    // -------------------------------------------------------------------------
    // SRM residue output
    // -------------------------------------------------------------------------
    logic signed [WEIGHT_WIDTH-1:0] srm_residue_q;

    // -------------------------------------------------------------------------
    // Calibration controller
    // -------------------------------------------------------------------------
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
        .comp_out     (calib_comp_out),
        .dac_p_force  (dac_p_force),
        .dac_n_force  (dac_n_force),
        .w_wr_en      (w_wr_en),
        .w_wr_addr    (w_wr_addr),
        .w_wr_data    (w_wr_data)
    );

    // -------------------------------------------------------------------------
    // SRM residue estimator
    // -------------------------------------------------------------------------
    srm_residue_estimator #(
        .DECISION_COUNT (SRM_DECISIONS),
        .RESIDUE_WIDTH  (WEIGHT_WIDTH),
        .FRAC_BITS      (FRAC_BITS)
    ) u_srm_residue (
        .clk            (clk),
        .rst_n          (rst_n),
        .start          (srm_start),
        .decision_valid (srm_decision_valid),
        .decision_bit   (srm_decision_bit),
        .busy           (srm_busy),
        .done           (srm_done),
        .decision_index (srm_decision_index),
        .ones_count     (srm_ones_count),
        .residue_q      (srm_residue_q)
    );

    // -------------------------------------------------------------------------
    // Reconstruction datapath
    // -------------------------------------------------------------------------
    sar_reconstruction #(
        .CAP_NUM         (CAP_NUM),
        .WEIGHT_WIDTH    (WEIGHT_WIDTH),
        .OUTPUT_WIDTH    (OUTPUT_WIDTH),
        .FRAC_BITS       (FRAC_BITS),
        .MAX_CALIB_BIT   (MAX_CALIB_BIT),
        .INIT_WEIGHT_LSB (REF_WEIGHT_LSB)
    ) u_reconstruction (
        .clk            (clk),
        .rst_n          (rst_n),
        .data_valid_in  (data_valid_in),
        .raw_bits       (raw_bits),
        .w_wr_en        (w_wr_en),
        .w_wr_addr      (w_wr_addr),
        .w_wr_data      (w_wr_data),
        .srm_residue    (srm_residue_q),
        .adc_dout       (adc_dout),
        .data_valid_out (data_valid_out)
    );

endmodule
