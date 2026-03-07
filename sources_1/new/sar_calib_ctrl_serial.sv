`timescale 1ns/1ps

// =============================================================================
// File Name     : sar_calib_ctrl_serial.sv
// Module Name   : sar_calib_ctrl_serial
// Description   : High-Precision Split-Sampling SAR ADC Foreground Recursive Calibration Controller (Serial Version)
//
// Functionality :
//   Implements recursive calibration algorithm based on "Measure-then-Set" strategy.
//   Uses lower calibrated capacitors (stored in Shadow RAM) as reference DAC to
//   measure actual weights of higher capacitors through binary search.
//   v2.0 introduces serial computation architecture for timing optimization and
//   enhanced ASIC reset reliability.
//
// Key Features  :
//   1. Recursive Measurement: Uses lower bit combinations to measure higher bits
//   2. Serial Accumulation: [v2.0 New] Multi-cycle weight calculation, eliminates combinational logic timing bottleneck
//   3. Offset Cancellation: Uses (P+N)/2 differential measurement method
//   4. MSB Protection: Forces inversion of second-highest bit to compress common-mode range, compensates in digital domain
//   5. ASIC Safe Reset: [v2.0 New] Synchronous reset loads reference weights, replaces initial blocks
//
// Parameters    :
//   CAP_NUM       : Total capacitor bit count (default 20)
//   WEIGHT_WIDTH  : Weight fixed-point bit width (default 30, Q18.12)
//   COMP_WAIT_CYC : Comparator/DAC settling time cycles (default 16)
//   AVG_LOOPS     : Averaging count (default 32, must be power of 2)
//   MAX_CALIB_BIT : Highest bit of calibration-free LSB segment (default 5)
//
// Ports         :
//   clk           : System clock
//   rst_n         : Asynchronous reset (active low)
//   start_calib   : Calibration start pulse
//   calib_done    : Calibration complete flag
//   calib_mode_en : Calibration mode enable indicator
//   comp_out      : Comparator output (1: Vp > Vn)
//   dac_p_force   : P-side DAC force control signal
//   dac_n_force   : N-side DAC force control signal
//   w_wr_en       : Weight write-back enable
//   w_wr_addr     : Weight write-back address
//   w_wr_data     : Weight write-back data
//
// Design Notes  :
//   1. [CRITICAL] Special protection logic (Bit-Swapping) enabled for Bit 18/19 calibration
//   2. [TIMING]   Weight calculation split into S_PHASE_x_CALC states, requires CAP_NUM clock cycles
//   3. [ASIC]     After reset release, Shadow RAM lower bits automatically load ideal values
// =============================================================================

module sar_calib_ctrl_serial #(
    parameter int CAP_NUM       = 20,            // Total capacitor bit count (Bit 0 ~ Bit 19)
    parameter int WEIGHT_WIDTH  = 30,            // Weight fixed-point bit width (Q18.12, reference 256.0)
    parameter int COMP_WAIT_CYC = 16,            // Comparator/DAC settling time (clock cycles)
    parameter int AVG_LOOPS     = 32,            // Averaging count (must be power of 2)
    parameter int MAX_CALIB_BIT = 5              // Trusted LSB segment highest bit (Bit 0-5 calibration-free)
)(
    // --- Global Signals ---
    input  logic                          clk,
    input  logic                          rst_n,
    
    // --- Control Plane ---
    input  logic                          start_calib,    // Start pulse
    output logic                          calib_done,     // Complete flag
    output logic                          calib_mode_en,  // Status indicator
    
    // --- Analog Front End (AFE) ---
    input  logic                          comp_out,       // Comparator output (1: Vp > Vn)
    output logic [CAP_NUM-1:0]            dac_p_force,    // P-side DAC force control
    output logic [CAP_NUM-1:0]            dac_n_force,    // N-side DAC force control
    
    // --- Register File Write-Back ---
    output logic                          w_wr_en,
    output logic [4:0]                    w_wr_addr,
    output logic signed [WEIGHT_WIDTH-1:0] w_wr_data
);

    // Calculate shift amount: log2(32) = 5
    localparam AVG_SHIFT = $clog2(AVG_LOOPS);

    // =========================================================================
    // 1. State Machine Definition (FSM)
    // =========================================================================
    typedef enum logic [3:0] {
        S_IDLE,           // Idle state
        S_INIT_TARGET,    // Initialize target bit
        
        // Phase P Sequence
        S_PHASE_P_SETUP,  // Phase P setup: set protection bits and search range
        S_PHASE_P_SAR,    // Phase P execute: binary search
        S_PHASE_P_CALC,   // Phase P calculate: [v2.0 New] serial weight accumulation
        
        // Phase N Sequence
        S_PHASE_N_SETUP,  // Phase N setup: reverse connection
        S_PHASE_N_SAR,    // Phase N execute: binary search
        S_PHASE_N_CALC,   // Phase N calculate: [v2.0 New] serial weight accumulation
        
        S_ACCUMULATE,     // Accumulate operation: Sum += P + N
        S_UPDATE_WEIGHT,  // Update weight: calculate average and write to Shadow RAM
        S_DONE            // Calibration complete
    } state_t;

    state_t state, next_state;

    // =========================================================================
    // 2. Internal Signal Declaration
    // =========================================================================
    // Control counters
    logic [4:0]  target_bit;  // Current target bit being calibrated (6~19)
    logic [5:0]  avg_cnt;     // Averaging counter
    logic [7:0]  wait_cnt;    // Settling time counter
    
    // SAR core logic
    logic [4:0]             sar_ptr;   // Current trial bit pointer
    logic [CAP_NUM-1:0]     sar_code;  // SAR search codeword
    
    // Serial computation logic [v2.0 New]
    logic [4:0]             calc_cnt;  // Serial accumulation counter
    logic signed [WEIGHT_WIDTH+5:0] temp_acc; // Temporary accumulator (overflow protection)
    
    // Arithmetic unit
    logic signed [WEIGHT_WIDTH+AVG_SHIFT+2:0] accumulator;        // Total average accumulator
    logic signed [WEIGHT_WIDTH-1:0]           meas_val_p;         // Phase P measurement result
    logic signed [WEIGHT_WIDTH-1:0]           meas_val_n;         // Phase N measurement result
    logic signed [WEIGHT_WIDTH-1:0]           calc_result_wire;   // Average calculation result

    // Shadow register (Shadow RAM)
    // [CRITICAL] Stores known capacitor weights required for recursive algorithm
    logic signed [WEIGHT_WIDTH-1:0] shadow_weights [CAP_NUM];

    logic comp_out_r;  // Comparator output registered for synchronization

    // =========================================================================
    // 3. State Machine Transition Logic
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= S_IDLE;
        else        state <= next_state;
    end

    always_comb begin
        next_state = state;
        case (state)
            S_IDLE:           if (start_calib) next_state = S_INIT_TARGET; else next_state = S_IDLE;
            S_INIT_TARGET:    next_state = S_PHASE_P_SETUP;
            
            // Phase P: Setup -> SAR Loop -> Calc Loop -> Next
            S_PHASE_P_SETUP:  next_state = S_PHASE_P_SAR;
            S_PHASE_P_SAR:    if (wait_cnt == 0 && sar_ptr == 0) next_state = S_PHASE_P_CALC; 
                              else next_state = S_PHASE_P_SAR;
            S_PHASE_P_CALC:   if (calc_cnt == CAP_NUM) next_state = S_PHASE_N_SETUP; // Wait for serial calculation complete
                              else next_state = S_PHASE_P_CALC;
            
            // Phase N: Setup -> SAR Loop -> Calc Loop -> Next
            S_PHASE_N_SETUP:  next_state = S_PHASE_N_SAR;
            S_PHASE_N_SAR:    if (wait_cnt == 0 && sar_ptr == 0) next_state = S_PHASE_N_CALC; 
                              else next_state = S_PHASE_N_SAR;
            S_PHASE_N_CALC:   if (calc_cnt == CAP_NUM) next_state = S_ACCUMULATE;    // Wait for serial calculation complete

            // Loop and update judgment
            S_ACCUMULATE:     if (avg_cnt == AVG_LOOPS - 1) next_state = S_UPDATE_WEIGHT;
                              else next_state = S_PHASE_P_SETUP;
                              
            S_UPDATE_WEIGHT:  if (target_bit == CAP_NUM - 1) next_state = S_DONE;
                              else next_state = S_INIT_TARGET;
            
            S_DONE:           next_state = S_DONE;
            default:          next_state = S_IDLE;
        endcase
    end

    // =========================================================================
    // 4. Core Data Path (Sequential Logic)
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            calib_done <= 0; calib_mode_en <= 0; target_bit <= MAX_CALIB_BIT + 1;
            avg_cnt <= 0; sar_code <= 0; sar_ptr <= 0; wait_cnt <= 0;
            accumulator <= 0; w_wr_en <= 0; w_wr_addr <= 0; w_wr_data <= 0;
            comp_out_r <= 0; meas_val_p <= 0; meas_val_n <= 0;
            calc_cnt <= 0; temp_acc <= 0;
            
            // [ASIC Safe Initialization]
            // Initialize reference weights during reset phase, replaces original initial block, ensures ASIC compatibility
            for(int i=0; i<CAP_NUM; i++) shadow_weights[i] <= 0;
            shadow_weights[0] <= 30'd256;  // Bit 0 = 1.0
            shadow_weights[1] <= 30'd512;  // Bit 1 = 2.0
            shadow_weights[2] <= 30'd1024;
            shadow_weights[3] <= 30'd2048;
            shadow_weights[4] <= 30'd4096;
            shadow_weights[5] <= 30'd8192; // Bit 5 = 32.0
            
        end else begin
            w_wr_en <= 0;
            comp_out_r <= comp_out; // Input synchronization

            case (state)
                S_IDLE: begin
                    calib_done <= 0; calib_mode_en <= 0;
                    target_bit <= MAX_CALIB_BIT + 1;
                end
                
                S_INIT_TARGET: begin
                    calib_mode_en <= 1; accumulator <= 0; avg_cnt <= 0;
                end

                // =============================================================
                // PHASE P: SAR Search -> Serial Calc
                // =============================================================
                S_PHASE_P_SETUP: begin
                    sar_code <= 0;
                    // [MSB Protection] Avoid protection bits, prevent double counting
                    if (target_bit >= 18) sar_ptr <= 16; else sar_ptr <= target_bit - 1;
                    wait_cnt <= COMP_WAIT_CYC;
                end

                S_PHASE_P_SAR: begin
                    if (wait_cnt == COMP_WAIT_CYC) begin
                         sar_code[sar_ptr] <= 1; wait_cnt <= wait_cnt - 1; // Trial
                    end else if (wait_cnt > 0) begin
                         wait_cnt <= wait_cnt - 1;
                    end else begin
                        if (!comp_out_r) sar_code[sar_ptr] <= 0; // Drop if P > N
                        if (sar_ptr > 0) begin
                            sar_ptr <= sar_ptr - 1; wait_cnt <= COMP_WAIT_CYC;
                        end else begin
                            calc_cnt <= 0; temp_acc <= 0; // SAR complete, start serial calculation
                        end
                    end
                end

                S_PHASE_P_CALC: begin
                    if (calc_cnt < CAP_NUM) begin
                        // [Serial Accumulation] Bit-by-bit accumulation, timing optimization
                        if (sar_code[calc_cnt]) temp_acc <= temp_acc + shadow_weights[calc_cnt];
                        calc_cnt <= calc_cnt + 1;
                    end else begin
                        // [Digital Restoration] Compensate protection bit weights
                        automatic logic signed [WEIGHT_WIDTH+5:0] final_val = temp_acc;
                        if (target_bit == 18) final_val += shadow_weights[17];
                        if (target_bit == 19) final_val += shadow_weights[18] + shadow_weights[17];
                        meas_val_p <= signed'(final_val[WEIGHT_WIDTH-1:0]);
                    end
                end

                // =============================================================
                // PHASE N: SAR Search -> Serial Calc
                // =============================================================
                S_PHASE_N_SETUP: begin
                    sar_code <= 0;
                    if (target_bit >= 18) sar_ptr <= 16; else sar_ptr <= target_bit - 1;
                    wait_cnt <= COMP_WAIT_CYC;
                end

                S_PHASE_N_SAR: begin
                    if (wait_cnt == COMP_WAIT_CYC) begin
                         sar_code[sar_ptr] <= 1; wait_cnt <= wait_cnt - 1;
                    end else if (wait_cnt > 0) begin
                         wait_cnt <= wait_cnt - 1;
                    end else begin
                        if (comp_out_r) sar_code[sar_ptr] <= 0; // Drop if N > P (Inverse logic)
                        if (sar_ptr > 0) begin
                            sar_ptr <= sar_ptr - 1; wait_cnt <= COMP_WAIT_CYC;
                        end else begin
                            calc_cnt <= 0; temp_acc <= 0;
                        end
                    end
                end

                S_PHASE_N_CALC: begin
                    if (calc_cnt < CAP_NUM) begin
                        if (sar_code[calc_cnt]) temp_acc <= temp_acc + shadow_weights[calc_cnt];
                        calc_cnt <= calc_cnt + 1;
                    end else begin
                        // [Digital Restoration] Compensate protection bit weights
                        automatic logic signed [WEIGHT_WIDTH+5:0] final_val = temp_acc;
                        if (target_bit == 18) final_val += shadow_weights[17];
                        if (target_bit == 19) final_val += shadow_weights[18] + shadow_weights[17];
                        meas_val_n <= signed'(final_val[WEIGHT_WIDTH-1:0]);
                    end
                end

                // =============================================================
                // Result Accumulation and Update
                // =============================================================
                S_ACCUMULATE: begin
                    accumulator <= accumulator + meas_val_p + meas_val_n;
                    avg_cnt <= avg_cnt + 1;
                end

                S_UPDATE_WEIGHT: begin
                    // 1. Write-back to external interface
                    w_wr_data <= calc_result_wire;
                    w_wr_addr <= target_bit;
                    w_wr_en   <= 1;
                    
                    // 2. [CRITICAL] Update Shadow RAM for next bit recursive use
                    shadow_weights[target_bit] <= calc_result_wire;
                    
                    if (target_bit == CAP_NUM - 1) begin 
                        calib_done <= 1; calib_mode_en <= 0; 
                    end else begin
                        target_bit <= target_bit + 1;
                    end
                end
            endcase
        end
    end

    // [Optimization] Use rounding instead of truncation to reduce recursive accumulation error
    // formula: (accumulator + 0.5) >> shift
    assign calc_result_wire = (accumulator + (1 << AVG_SHIFT)) >>> (AVG_SHIFT + 1);

    // =========================================================================
    // 5. Combinational Logic: DAC Drive Matrix (with MSB Protection)
    // =========================================================================
    always_comb begin
        dac_p_force = 0; dac_n_force = 0;
        
        // --- Phase P Drive ---
        if (state == S_PHASE_P_SAR || state == S_PHASE_P_SETUP || state == S_PHASE_P_CALC) begin
            dac_p_force[target_bit] = 1; 
            dac_n_force = sar_code;       
            // [MSB Protection Mapping]
            if (target_bit == 18) dac_n_force[17] = 1; 
            if (target_bit == 19) begin dac_n_force[18] = 1; dac_n_force[17] = 1; end
        end 
        // --- Phase N Drive ---
        else if (state == S_PHASE_N_SAR || state == S_PHASE_N_SETUP || state == S_PHASE_N_CALC) begin
            dac_n_force[target_bit] = 1; 
            dac_p_force = sar_code;       
            // [MSB Protection Mapping]
            if (target_bit == 18) dac_p_force[17] = 1; 
            if (target_bit == 19) begin dac_p_force[18] = 1; dac_p_force[17] = 1; end
        end
    end

endmodule
