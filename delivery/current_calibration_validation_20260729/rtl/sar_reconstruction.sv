`timescale 1ns/1ps

// =============================================================================
// File Name     : sar_reconstruction.sv
// Module Name   : sar_reconstruction
// Description   : SAR ADC Digital Reconstruction Engine
//                 For split-sampling architecture, processes raw SAR data
//                 through weighted summation to produce high-precision 16-bit digital output.
//
// Functionality : V_out = (Sum (D_i * W_i)) * Scale_Factor + Offset_Comp
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
//   w_wr_data      : Calibrated weight value (30-bit signed)
//   srm_residue    : SRM residue correction in the same Q format as weights
//   adc_dout       : Reconstructed ADC output (16-bit signed)
//   data_valid_out : Output valid flag
//
// Design Notes  :
//   1. Weight storage resets lower trusted bits to ideal values, then accepts calibration writes
//   2. Reconstruction uses two-stage pipeline: first stage accumulates, second stage rounds/saturates
//      [Update] For timing optimization, first stage accumulation split into Pipeline Stage 1 (Partial) and Stage 2 (Global)
//   3. srm_residue is added after differential normalization and before output
//      rounding, matching the SRM-assisted reconstruction model.
//   4. +0.5 LSB ensures correct rounding, compensating for Floor truncation -0.5 LSB systematic offset
//   5. All intermediate calculations use explicit signed arithmetic to prevent Verilog type inference issues
// =============================================================================

module sar_reconstruction #(
    parameter int CAP_NUM       = 20,
    parameter int WEIGHT_WIDTH  = 30, // [Design Note] Must be >= 28 to support MSB weight
    parameter int OUTPUT_WIDTH  = 16,
    parameter int FRAC_BITS     = 8,
    parameter int MAX_CALIB_BIT = 5,
    parameter int INIT_WEIGHT_LSB = 256
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
    input  logic signed [WEIGHT_WIDTH-1:0] w_wr_data,    // Calibrated weight value
    input  logic signed [WEIGHT_WIDTH-1:0] srm_residue,  // SRM residue correction

    // --- Data Path Output (To User/Bus) ---
    output logic signed [OUTPUT_WIDTH-1:0] adc_dout,      // Reconstructed ADC output
    output logic                          data_valid_out // Output valid flag
);

    // =========================================================================
    // 1. Local Weight Memory Array
    // =========================================================================
    // Stores the binary weight for each bit. The lower trusted segment is reset to
    // ideal weights because foreground calibration starts at MAX_CALIB_BIT + 1.
    logic signed [WEIGHT_WIDTH-1:0] weight_ram [0:CAP_NUM-1];

    // Synchronous write port with reset defaults for the calibration-free LSBs.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int k=0; k<CAP_NUM; k++) begin
                if (k <= MAX_CALIB_BIT)
                    weight_ram[k] <= INIT_WEIGHT_LSB <<< k;
                else
                    weight_ram[k] <= '0;
            end
        end else if (w_wr_en && (w_wr_addr < CAP_NUM)) begin
            weight_ram[w_wr_addr] <= w_wr_data;
        end
    end

    // =========================================================================
    // 2. Two-Stage Pipeline Optimization: Partial Accumulation (Stage 1)
    // =========================================================================
    // Original logic: single-cycle accumulation of 20 x 40-bit adders was critical path bottleneck.
    // Optimized to two-stage pipeline:
    // Stage 1: Divide 20 inputs into 4 groups, compute 4 partial sums in parallel.
    // =========================================================================
    logic signed [39:0] partial_sums [0:3];
    logic               vld_pipe_s1;

    // 20 inputs / 4 groups = 5 inputs per group
    localparam int GROUP_SIZE = 5;

    // =========================================================================
    // Parameter Guards — lock the configuration validated for SAR ADC V3
    // =========================================================================
    initial begin : p_parameter_guard
        if (CAP_NUM != 20) begin
            $error("sar_reconstruction: 4x5 partial-sum pipeline is qualified for CAP_NUM=20 only.");
        end
        if (WEIGHT_WIDTH < 30) begin
            $error("sar_reconstruction: WEIGHT_WIDTH must be >= 30 for the current calibrated weight range.");
        end
        if (OUTPUT_WIDTH != 16) begin
            $error("sar_reconstruction: output saturation constants are qualified for OUTPUT_WIDTH=16 only.");
        end
        if (FRAC_BITS != 8) begin
            $error("sar_reconstruction: current project fixed-point contract requires FRAC_BITS=8.");
        end
        if (MAX_CALIB_BIT < 0 || MAX_CALIB_BIT >= CAP_NUM) begin
            $error("sar_reconstruction: MAX_CALIB_BIT must be in [0, CAP_NUM-1].");
        end
        if (INIT_WEIGHT_LSB <= 0) begin
            $error("sar_reconstruction: INIT_WEIGHT_LSB must be positive.");
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for(int k=0; k<4; k++) partial_sums[k] <= 0;
            vld_pipe_s1 <= 0;
        end else begin
            if (data_valid_in) begin
                for (int g=0; g<4; g++) begin
                    automatic logic signed [39:0] acc_group = 0;
                    for (int i=0; i<GROUP_SIZE; i++) begin
                        automatic int idx = g * GROUP_SIZE + i;
                        if (idx < CAP_NUM) begin
                            // [CRITICAL DESIGN] Force signed type conversion
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
    // Sum all partial sums to get final accumulated sum_stage2
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
    // 4. Two-Stage Pipeline: Scaling, Offset Compensation and Saturation
    // =========================================================================
    // Target: Map 40-bit high-precision result to 16-bit range [-32768, +32767].
    //
    // Processing steps:
    //   a. Divide by 2 (ASR): Since accumulated dynamic range is 2*Vref, divide by 2 first
    //   b. Add 0.5 LSB: Compensate for Floor truncation -0.5 LSB systematic offset (DC Offset)
    //   c. Arithmetic shift: Remove fractional bits, round to target precision
    //   d. Saturation clamp: Prevent overflow/underflow and sign inversion
    // =========================================================================

    // [Fix] Shift amount calculation
    // Weight W19 ~ 2^23 (Q22.8), target MSB ~ 2^15.
    // 2^23 -> 2^15 requires right shift of 8 bits.
    // Original formula (20-16)+8 = 12 would result in too small output range.
    // Correct shift amount should be FRAC_BITS (consistent with weight voltage normalization)
    localparam int TOTAL_SHIFT = FRAC_BITS;

    // Intermediate variables (explicit declaration for Debug and simulation observation)
    logic signed [39:0] val_step1_div2;
    logic signed [39:0] val_step2_round;
    logic signed [39:0] val_step3_shift;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            adc_dout <= 0;
            data_valid_out <= 0;
        end else begin
            if (vld_pipe_s2) begin
                // Step 1: Divide by 2 and add SRM residue correction.
                // srm_residue is already expressed in the same Q format as the
                // calibrated capacitor weights, so it must be injected before
                // FRAC_BITS output scaling.
                val_step1_div2 = (sum_stage2 >>> 1) + signed'(40'(srm_residue));

                // Step 2: Add 0.5 LSB rounding compensation (Round to Nearest)
                // [CRITICAL DESIGN] Must use '40'sd1' because it's signed arithmetic
                // Writing '1' alone would be treated as unsigned, causing incorrect results
                // when sum_stage2 is negative (treated as large positive number)
                val_step2_round = val_step1_div2 + (40'sd1 <<< (TOTAL_SHIFT - 1));

                // Step 3: Arithmetic right shift (rounding)
                val_step3_shift = val_step2_round >>> TOTAL_SHIFT;

                // Step 4: Saturation Logic
                // Check if result exceeds 16-bit signed range
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
