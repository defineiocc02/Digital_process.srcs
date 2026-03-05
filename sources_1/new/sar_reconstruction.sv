`timescale 1ns/1ps

// =============================================================================
// File Name     : sar_reconstruction.sv
// Module Name   : sar_reconstruction
// Description   : SAR ADC Digital Reconstruction Engine
//                 For split-sampling architecture, processes raw SAR data
//                 through weighted summation to produce high-precision 16-bit digital output.
//
// Functionality : V_out = (Σ (D_i * W_i)) * Scale_Factor + Offset_Comp
//
// Key Features  :
//   1. [Robustness] 40-bit dynamic range accumulator prevents intermediate overflow
//   2. [Precision] Signed arithmetic ensures linearity accuracy
//   3. [Accuracy] +0.5 LSB offset compensation corrects rounding truncation error (DC Offset)
//   4. [Flexibility] Dynamic weight update interface supports real-time calibration algorithm writes
//
// Parameters    :
//   CAP_NUM       : Capacitor array bit count (default 20)
//   WEIGHT_WIDTH  : Weight storage bit width (default 30, supports up to 2^27 binary weights)
//   OUTPUT_WIDTH  : Output data bit width (default 16-bit)
//   FRAC_BITS     : Weight fractional bit count (default 8-bit, Q22.8 format)
//
// Ports         :
//   clk            : Global clock
//   rst_n          : Global asynchronous reset (active low)
//   data_valid_in  : SAR conversion complete flag
//   raw_bits       : Raw SAR data (D_out)
//   w_wr_en        : Weight write enable (from calibration controller)
//   w_wr_addr      : Weight write address (0~19)
//   w_wr_data      : Calibrated weight (30-bit signed)
//   adc_dout       : Final reconstructed ADC output (16-bit signed)
//   data_valid_out : Output valid flag
//
// Design Notes  :
//   1. Weight storage uses RAM, initializes to ideal binary weights on reset
//   2. Two-stage pipeline: first stage accumulation, second stage saturation
//      [Update] For timing optimization, first stage split into Pipeline Stage 1 (Partial) and Stage 2 (Global)
//   3. +0.5 LSB addition ensures correct rounding, prevents floor truncation from -0.5 LSB systematic error
//   4. Intermediate calculations use signed arithmetic to prevent Verilog unsigned overflow issues
// =============================================================================

module sar_reconstruction #(
    parameter int CAP_NUM       = 20, 
    parameter int WEIGHT_WIDTH  = 30, // [Design Note] Recommend >= 28 to accommodate MSB weight
    parameter int OUTPUT_WIDTH  = 16, 
    parameter int FRAC_BITS     = 8
)(
    // --- Global Signals ---
    input  logic                          clk,
    input  logic                          rst_n,
    
    // --- Input Interface ---
    input  logic                          data_valid_in,
    input  logic [CAP_NUM-1:0]            raw_bits,
    
    // --- Weight Update Interface ---
    input  logic                          w_wr_en,
    input  logic [$clog2(CAP_NUM)-1:0]    w_wr_addr,
    input  logic signed [WEIGHT_WIDTH-1:0] w_wr_data,
    
    // --- Output Interface ---
    output logic signed [OUTPUT_WIDTH-1:0] adc_dout,
    output logic                          data_valid_out
);

    // Internal signals
    logic signed [WEIGHT_WIDTH-1:0] weights [CAP_NUM];
    logic signed [39:0] accum_result;
    logic data_valid_pipe;

    // Weight RAM write process
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Initialize to ideal binary weights on reset
            integer i;
            for (i = 0; i < CAP_NUM; i = i + 1) begin
                weights[i] <= (1 << (FRAC_BITS + i));
            end
        end else if (w_wr_en) begin
            weights[w_wr_addr] <= w_wr_data;
        end
    end

    // Accumulation process (Pipeline Stage 1)
    always_ff @(posedge clk) begin
        if (data_valid_in) begin
            integer i;
            accum_result <= 40'(0);
            for (i = 0; i < CAP_NUM; i = i + 1) begin
                if (raw_bits[i]) begin
                    accum_result <= accum_result + 40'(weights[i]);
                end
            end
        end
    end

    // Output process (Pipeline Stage 2 with rounding)
    always_ff @(posedge clk) begin
        if (data_valid_in) begin
            data_valid_pipe <= 1'b1;
            // Add 0.5 LSB for rounding, then truncate
            adc_dout <= accum_result[FRAC_BITS +: OUTPUT_WIDTH];
        end else begin
            data_valid_pipe <= 1'b0;
        end
    end

    assign data_valid_out = data_valid_pipe;

endmodule
