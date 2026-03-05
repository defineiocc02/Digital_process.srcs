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
//   4. [Flexibility] Dynamic weight update interface supports foreground calibration algorithm writes
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
//   1. Weight storage uses local RAM, initializes to ideal values on reset
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
    
    // --- Data Path Input (From SAR Logic) ---
    input  logic                          data_valid_in, // SAR conversion complete flag
    input  logic [CAP_NUM-1:0]            raw_bits,      // Raw SAR data (D_out)
    
    // --- Calibration Interface (From Calib Ctrl) ---
    input  logic                          w_wr_en,       // Write enable
    input  logic [4:0]                    w_wr_addr,     // Weight address (0~19)
    input  logic signed [WEIGHT_WIDTH-1:0] w_wr_data,    // Calibrated weight
    
    // --- Data Path Output (To User/Bus) ---
    output logic signed [OUTPUT_WIDTH-1:0] adc_dout,      // Final reconstructed ADC output
    output logic                          data_valid_out // Output valid flag
);

    // =========================================================================
    // 1. Local Weight Memory
    // =========================================================================
    // Stores actual weight for each bit.
    // Initial values are ideal, actual usage requires sar_calib_ctrl module to write calibrated values.
    logic signed [WEIGHT_WIDTH-1:0] weight_ram [0:CAP_NUM-1];

    initial begin
        for (int k=0; k<CAP_NUM; k++) weight_ram[k] = 30'd0;
    end

    // Synchronous write port
    always_ff @(posedge clk) begin
        if (w_wr_en) weight_ram[w_wr_addr] <= w_wr_data;
    end

    // =========================================================================
    // 2. Two-Stage Pipeline Optimization: Partial Accumulation (Stage 1)
    // =========================================================================
    // Original logic: one cycle accumulates 20 x 40-bit adders, critical path bottleneck
    // Optimized to four-stage pipeline:
    // Stage 1: Divide 20 inputs into 4 groups, calculate 4 partial sums
    // =========================================================================
    logic signed [39:0] partial_sums [0:3]; 
    logic               vld_pipe_s1;
    
    // 20 inputs / 4 groups = 5 inputs per group
    localparam int GROUP_SIZE = 5; 

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for(int k=0; k<4; k++) partial_sums[k] <= 0;
            vld_pipe_s1 <= 0;
        end else begin
            if (data_valid_in) begin
                for (int g=0; g<4; g++) begin
                    automatic logic signed [39:0] acc_group = 0;
                    for (int i=0; i<GROUP_SIZE; i++) begin
                        int idx = g * GROUP_SIZE + i;
                        if (idx < CAP_NUM) begin
                            // [CRITICAL DESIGN] Force signed conversion
                            if (raw_bits[idx]) 
                                acc_group = acc_group + signed'(40'(weight_ram[idx]));
                            else             
                                acc_group = acc_group - signed'(40'(weight_ram[idx]));
                        end
                    end
                    partial_sums[g] <= acc_group;
                end
                vld_pipe_s1 <= 1;
            end else begin
                vld_pipe_s1 <= 0;
            end
        end
    end

    // =========================================================================
    // 3. Two-Stage Pipeline Optimization: Global Accumulation (Stage 2)
    // =========================================================================
    // Sum partial sums to get final result sum_stage2
    // =========================================================================
    logic signed [39:0] sum_stage2;
    logic               vld_pipe_s2;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sum_stage2 <= 0;
            vld_pipe_s2 <= 0;
        end else begin
            if (vld_pipe_s1) begin
                sum_stage2 <= partial_sums[0] + partial_sums[1] + 
                              partial_sums[2] + partial_sums[3];
                vld_pipe_s2 <= 1;
            end else begin
                vld_pipe_s2 <= 0;
            end
        end
    end

    // =========================================================================
    // 4. Two-Stage Pipeline Output: Scaling, Offset Compensation and Saturation
    // =========================================================================
    // Goal: Map 40-bit high-precision result to 16-bit output range [-32768, +32767]
    //
    // Processing steps:
    //   a. Divide by 2 (ASR): Because accumulated dynamic range is 2*Vref, normalize first
    //   b. Add 0.5 LSB: Correct floor truncation from -0.5 LSB systematic error (DC Offset)
    //   c. Right shift: Remove fractional bits, round to target resolution
    //   d. Saturation clamp: Prevent overflow values from causing wrap-around
    // =========================================================================
    
    // [Fix] Shift bit count
    // Weight W19 ~ 2^23 (Q22.8), max MSB ~ 2^15. 
    // 2^23 -> 2^15 requires right shift 8 bits
    // Original formula (20-16)+8 = 12 would cause precision loss
    // Correct shift count should be FRAC_BITS (consistent with weight voltage normalization)
    localparam int TOTAL_SHIFT = FRAC_BITS; 

    // Intermediate variables (explicit declaration for Debug and waveform observation)
    logic signed [39:0] val_step1_div2;
    logic signed [39:0] val_step2_round;
    logic signed [39:0] val_step3_shift;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            adc_dout <= 0;
            data_valid_out <= 0;
        end else begin
            if (vld_pipe_s2) begin
                // Step 1: Divide by 2 (arithmetic right shift, preserve sign bit)
                val_step1_div2 = sum_stage2 >>> 1;
                
                // Step 2: Add 0.5 LSB for rounding (Round to Nearest)
                // [CRITICAL DESIGN] Must use '40'sd1' because it's signed constant
                // Writing '1' directly would be interpreted as unsigned, causing incorrect negative rounding
                val_step2_round = val_step1_div2 + (40'sd1 <<< (TOTAL_SHIFT - 1));
                
                // Step 3: Right shift (remove fractional bits)
                val_step3_shift = val_step2_round >>> TOTAL_SHIFT;
                
                // Step 4: Saturation (Saturation Logic)
                // Check if exceeds 16-bit signed range
                if (val_step3_shift > 32767)       
                    adc_dout <= 32767;
                else if (val_step3_shift < -32768) 
                    adc_dout <= -32768;
                else                       
                    adc_dout <= val_step3_shift[15:0]; // Safe truncation
                
                data_valid_out <= 1;
            end else begin
                data_valid_out <= 0;
            end
        end
    end

endmodule
