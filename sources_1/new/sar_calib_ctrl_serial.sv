`timescale 1ns/1ps

// =============================================================================
// File Name     : sar_calib_ctrl_serial.sv
// Module Name   : sar_calib_ctrl_serial
// Description   : High-Precision Split-Sampling SAR ADC Foreground Recursive Calibration Controller (Serial Version)
//
// Functionality :
//   Implements "Measure-then-Set" recursive calibration algorithm. Measures lower bit calibration data,
//   stores in Shadow RAM, and uses as reference DAC for upper bit measurement to calculate actual weight.
//   v2.0 adds serial accumulation architecture to optimize timing and enhance ASIC unit reliability.
//
// Key Features  :
//   1. Recursive Measurement: Measure lower bits first, then upper bits
//   2. Serial Accumulation: [v2.0 New] Serial weight calculation, relaxes critical timing path
//   3. Offset Cancellation: Use (P+N)/2 to eliminate offset
//   4. MSB Protection: Force bridge capacitor to maintain differential input range
//   5. ASIC Safe Reset: [v2.0 New] Synchronous reset initializes standard weights, no initial block
//
// Parameters    :
//   CAP_NUM       : Total capacitor bits (default 20)
//   WEIGHT_WIDTH  : Weight data bit width (default 30, Q18.12)
//   COMP_WAIT_CYC : Comparator/DAC settling wait cycles (default 16)
//   AVG_LOOPS     : Average count (default 32, must be power of 2)
//   MAX_CALIB_BIT : Skip calibration LSB bit count (default 5)
//
// Ports         :
//   clk           : System clock
//   rst_n         : Asynchronous reset (active low)
//   start_calib   : Calibration start trigger
//   calib_done    : Calibration complete flag
//   calib_mode_en : Calibration mode enable indicator
//   comp_out      : Comparator output (1: Vp > Vn)
//   dac_p_force   : P-side DAC force control signal
//   dac_n_force   : N-side DAC force control signal
//   w_wr_en       : Weight write enable
//   w_wr_addr     : Weight write address
//   w_wr_data     : Weight write data
//
// Design Notes  :
//   1. [CRITICAL] Bit 18/19 calibration requires special protection logic (Bit-Swapping)
//   2. [TIMING]   Weight calculation moved to S_PHASE_x_CALC state, requires CAP_NUM clock cycles
//   3. [ASIC]     Reset release and Shadow RAM reset automatically load ideal values
// =============================================================================

module sar_calib_ctrl_serial #(
    parameter int CAP_NUM       = 20,            // Total capacitor bits (Bit 0 ~ Bit 19)
    parameter int WEIGHT_WIDTH  = 30,            // Weight data bit width (Q18.12, standard 256.0)
    parameter int COMP_WAIT_CYC = 16,            // Comparator/DAC settling time (clock cycles)
    parameter int AVG_LOOPS     = 32,            // Average count (must be power of 2)
    parameter int MAX_CALIB_BIT = 5              // Skip LSB bit count (Bit 0-5 not calibrated)
)(
    // --- Global Signals ---
    input  logic                          clk,
    input  logic                          rst_n,
    
    // --- Control Interface ---
    input  logic                          start_calib,    // Start trigger
    output logic                          calib_done,     // Complete flag
    output logic                          calib_mode_en,  // Status indicator
    
    // --- Analog Front-end (AFE) ---
    input  logic                          comp_out,       // Comparator output (1: Vp > Vn)
    output logic [CAP_NUM-1:0]            dac_p_force,    // P-side DAC force control
    output logic [CAP_NUM-1:0]            dac_n_force,    // N-side DAC force control
    
    // --- Register Write Interface ---
    output logic                          w_wr_en,
    output logic [4:0]                    w_wr_addr,
    output logic signed [WEIGHT_WIDTH-1:0] w_wr_data
);

    // Average shift bit count: log2(32) = 5
    localparam AVG_SHIFT = $clog2(AVG_LOOPS);

    // =========================================================================
    // 1. State Machine Definition (FSM)
    // =========================================================================
    typedef enum logic [3:0] {
        S_IDLE,           // Idle state
        S_INIT_TARGET,    // Initialize target bit
        
        // Phase P measurement
        S_PHASE_P_SETUP,  // P-side setup, set target bit and search range
        S_PHASE_P_SAR,    // P-side execution, binary search
        S_PHASE_P_CALC,   // P-side calculation: [v2.0 New] serial accumulation weight
        
        // Phase N measurement
        S_PHASE_N_SETUP,  // N-side setup, set search range
        S_PHASE_N_SAR,    // N-side execution, binary search
        S_PHASE_N_CALC,   // N-side calculation: [v2.0 New] serial accumulation weight
        
        S_ACCUMULATE,     // Accumulate partial sum: Sum += P + N
        S_UPDATE_WEIGHT,  // Update weight, average and write to Shadow RAM
        S_DONE            // Calibration complete
    } state_t;

    state_t state, next_state;

    // =========================================================================
    // 2. Internal Signal Definition
    // =========================================================================
    // Control counters
    logic [4:0]  target_bit;  // Current calibration target bit (6~19)
    logic [5:0]  avg_cnt;     // Average loop counter
    logic [7:0]  wait_cnt;    // Wait cycle counter
    
    // SAR search logic
    logic [4:0]             sar_ptr;   // Current binary search bit pointer
    logic [CAP_NUM-1:0]     sar_code;  // SAR search result
    
    // Serial calculation logic [v2.0 New]
    logic [4:0]             calc_cnt;  // Serial accumulation counter
    logic signed [WEIGHT_WIDTH+5:0] temp_acc; // Temporary accumulator (extended)
    
    // Data calculation unit
    logic signed [WEIGHT_WIDTH+AVG_SHIFT+2:0] accumulator;        // Pre-average accumulator
    logic signed [WEIGHT_WIDTH-1:0]           meas_val_p;         // P-side measurement
    logic signed [WEIGHT_WIDTH-1:0]           meas_val_n;         // N-side measurement
    logic signed [WEIGHT_WIDTH-1:0]           calc_result_wire;   // Average result wire

    // Shadow register (Shadow RAM)
    // [CRITICAL] Stores known weights from recursive algorithm
    logic signed [WEIGHT_WIDTH-1:0] shadow_weights [CAP_NUM];

    logic comp_out_r;  // Comparator output register sync

    // =========================================================================
    // 3. State Register Transfer Logic
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

            // Loop completion judgment
            S_ACCUMULATE:     if (avg_cnt == AVG_LOOPS - 1) next_state = S_UPDATE_WEIGHT;
                              else next_state = S_PHASE_P_SETUP;
                              
            S_UPDATE_WEIGHT:  if (target_bit == CAP_NUM - 1) next_state = S_DONE;
                              else next_state = S_INIT_TARGET;
            
            S_DONE:           next_state = S_DONE;
            default:          next_state = S_IDLE;
        endcase
    end

    // =========================================================================
    // 4. Data Path (Sequential Logic)
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            calib_done <= 0; calib_mode_en <= 0; target_bit <= MAX_CALIB_BIT + 1;
            avg_cnt <= 0; sar_code <= 0; sar_ptr <= 0; wait_cnt <= 0;
            accumulator <= 0; w_wr_en <= 0; w_wr_addr <= 0; w_wr_data <= 0;
            comp_out_r <= 0; meas_val_p <= 0; meas_val_n <= 0;
            calc_cnt <= 0; temp_acc <= 0;
            
            // [ASIC Safe Initialization]
            // Initialize standard weights at reset release, replaces initial block, ensures ASIC compatibility
            for(int i=0; i<CAP_NUM; i++) shadow_weights[i] <= 0;
            shadow_weights[0] <= 30'd256;  // Bit 0 = 1.0
            shadow_weights[1] <= 30'd512;  // Bit 1 = 2.0
            shadow_weights[2] <= 30'd1024;
            shadow_weights[3] <= 30'd2048;
            shadow_weights[4] <= 30'd4096;
            shadow_weights[5] <= 30'd8192; // Bit 5 = 32.0
            
        end else begin
            w_wr_en <= 0;
            comp_out_r <= comp_out; // Input sync

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
                    // [MSB Protection] Skip bridge capacitor bits to prevent duplicate forcing
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
                        // [Serial Accumulation] Bit-by-bit accumulation, optimize timing
                        if (sar_code[calc_cnt]) temp_acc <= temp_acc + shadow_weights[calc_cnt];
                        calc_cnt <= calc_cnt + 1;
                    end else begin
                        // [Digital Restoration] Add bridge capacitor bit weight
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
                        // [Digital Restoration] Add bridge capacitor bit weight
                        automatic logic signed [WEIGHT_WIDTH+5:0] final_val = temp_acc;
                        if (target_bit == 18) final_val += shadow_weights[17];
                        if (target_bit == 19) final_val += shadow_weights[18] + shadow_weights[17];
                        meas_val_n <= signed'(final_val[WEIGHT_WIDTH-1:0]);
                    end
                end

                // =============================================================
                // Average Accumulation
                // =============================================================
                S_ACCUMULATE: begin
                    accumulator <= accumulator + meas_val_p + meas_val_n;
                    avg_cnt <= avg_cnt + 1;
                end

                S_UPDATE_WEIGHT: begin
                    // 1. Write to external interface
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

    // [Optimization] Average calculation (Rounding) avoids truncation error, reduces recursive accumulation error
    // formula: (accumulator + 0.5) >> shift
    assign calc_result_wire = (accumulator + (1 << AVG_SHIFT)) >>> (AVG_SHIFT + 1);

    // =========================================================================
    // 5. Output Logic: DAC Drive Control (with MSB Protection)
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
