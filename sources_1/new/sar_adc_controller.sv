`timescale 1ns/1ps

// =============================================================================
// Module Name   : sar_adc_controller
// Description   : Hardware SAR Logic Controller (Successive Approximation Register)
//                 Equivalent to Force Task in Testbench, implements actual binary search algorithm
// =============================================================================
module sar_adc_controller #(
    parameter int CAP_NUM = 20  // ADC resolution (Bit 0 ~ 19)
)(
    input  wire                 clk,
    input  wire                 rst_n,
    
    // --- Control Interface (Handshake) ---
    input  wire                 start,        // Start conversion
    output reg                  eoc,          // End of Conversion
    output reg [CAP_NUM-1:0]    result_out,   // Final conversion result
    output reg                  result_valid, // Result valid flag
    
    // --- Analog Front-end Interface (PHY Interface) ---
    input  wire                 comp_out,     // Comparator output (1: DAC > Vin, 0: DAC < Vin)
    output reg  [CAP_NUM-1:0]   dac_p_force   // DAC control signal for capacitor array
);

    // --- State Machine ---
    typedef enum logic [1:0] {
        S_IDLE,    // Idle state
        S_SAMPLE,  // Sample state (preset all capacitors to sampling state)
        S_CONVERT, // Convert state (execute SAR loop)
        S_DONE     // Done state
    } state_t;

    state_t state;

    // --- Internal Registers ---
    logic [$clog2(CAP_NUM)-1:0] bit_ptr;  // Pointer: current bit being tested
    logic [CAP_NUM-1:0]         sar_reg;  // Register: stores SAR conversion result
    logic                       phase;    // Phase control: 0=Set DAC, 1=Latch Comp

    // =========================================================================
    // FSM & Datapath
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_IDLE;
            bit_ptr      <= CAP_NUM - 1;
            sar_reg      <= '0;
            phase        <= 0;
            eoc          <= 0;
            result_valid <= 0;
            result_out   <= '0;
        end else begin
            // Default reset
            eoc          <= 0;
            result_valid <= 0;

            case (state)
                S_IDLE: begin
                    sar_reg <= '0;
                    phase   <= 0;
                    if (start) state <= S_SAMPLE;
                end

                S_SAMPLE: begin
                    // Actual hardware uses bootstrap switches for capacitor array control
                    // Directly enter conversion, preset MSB (Bit 19)
                    state   <= S_CONVERT;
                    bit_ptr <= CAP_NUM - 1; 
                    
                    // [Set]: Preset MSB to 1 (Trial)
                    sar_reg              <= '0;
                    sar_reg[CAP_NUM - 1] <= 1'b1; 
                    phase   <= 0;
                end

                S_CONVERT: begin
                    if (phase == 0) begin
                        // --- Phase 0: DAC Settling ---
                        // Wait for DAC output voltage to settle, then trigger comparator
                        phase <= 1;
                    end else begin
                        // --- Phase 1: Comparator Latch & Shift ---
                        
                        // 1. Check current bit based on comparator output
                        // If comp_out=1 (DAC > Vin), current bit is too high, clear to 0
                        if (comp_out) begin
                            sar_reg[bit_ptr] <= 1'b0; 
                        end
                        // Otherwise keep 1

                        // 2. Shift logic
                        if (bit_ptr == 0) begin
                            state <= S_DONE;
                        end else begin
                            bit_ptr <= bit_ptr - 1;
                            // [Set]: Preset next bit to 1 (Next Trial)
                            // Note: Operate on next lower bit, current bit decision is final
                            sar_reg[bit_ptr - 1] <= 1'b1;
                            phase <= 0; // Return to Phase 0 for next comparison
                        end
                    end
                end

                S_DONE: begin
                    result_out   <= sar_reg;
                    result_valid <= 1;
                    eoc          <= 1;
                    state        <= S_IDLE;
                end
            endcase
        end
    end

    // --- Output Logic ---
    // Output internal register to PHY in real-time
    always_comb begin
        dac_p_force = sar_reg;
    end

endmodule
