`timescale 1ns/1ps

// =============================================================================
// Module Name   : sar_adc_controller
// Description   : SAR logic controller implemented in hardware (Successive Approximation Register)
//                 Unlike Testbench using Task, this implements actual hardware timing
// =============================================================================
module sar_adc_controller #(
    parameter int CAP_NUM = 20  // ADC resolution (Bit 0 ~ 19)
)(
    input  wire                 clk,
    input  wire                 rst_n,
    
    // --- Control Interface (Handshake) ---
    input  wire                 start,        // Start signal
    output reg                  eoc,          // End of Conversion
    output reg [CAP_NUM-1:0]    result_out,   // Conversion result output
    output reg                  result_valid, // Result valid flag
    
    // --- Analog Front End Interface (PHY Interface) ---
    input  wire                 comp_out,     // Comparator output (1: DAC > Vin, 0: DAC < Vin)
    output reg  [CAP_NUM-1:0]   dac_p_force   // Control signals for capacitor array
);

    // --- State Machine Definition ---
    typedef enum logic [1:0] {
        S_IDLE,    // Idle state
        S_SAMPLE,  // Sample state (pre-charge all capacitors)
        S_CONVERT, // Convert state (main SAR loop)
        S_DONE     // Done state
    } state_t;

    state_t state;

    // --- Internal Registers ---
    logic [$clog2(CAP_NUM)-1:0] bit_ptr;  // Pointer: current trial bit
    logic [CAP_NUM-1:0]         sar_reg;  // Register storing approximation sequence data
    logic                       phase;    // Two-phase control: 0=Set DAC, 1=Latch Comp

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
            // Default signal reset
            eoc          <= 0;
            result_valid <= 0;

            case (state)
                S_IDLE: begin
                    sar_reg <= '0;
                    phase   <= 0;
                    if (start) state <= S_SAMPLE;
                end

                S_SAMPLE: begin
                    // Actual hardware needs sampling switch control (Bootstrapped Switch)
                    // Here directly enter conversion, pre-set MSB (Bit 19)
                    state   <= S_CONVERT;
                    bit_ptr <= CAP_NUM - 1; 
                    
                    // [Trial]: Pre-set MSB to 1
                    sar_reg              <= '0;
                    sar_reg[CAP_NUM - 1] <= 1'b1; 
                    phase   <= 0;
                end

                S_CONVERT: begin
                    if (phase == 0) begin
                        // --- Phase 0: DAC Settling ---
                        // Wait for DAC output voltage to stabilize, comparator front-end amplifier settles
                        phase <= 1;
                    end else begin
                        // --- Phase 1: Comparator Latch & Shift ---
                        
                        // 1. Decide current bit based on comparator result (Check)
                        // If comp_out=1 (DAC > Vin), means trial 1 is too large, should clear (set 0)
                        if (comp_out) begin
                            sar_reg[bit_ptr] <= 1'b0; 
                        end
                        // Otherwise keep 1 (Keep)

                        // 2. Shift logic (Shift)
                        if (bit_ptr == 0) begin
                            state <= S_DONE;
                        end else begin
                            bit_ptr <= bit_ptr - 1;
                            // [Trial]: Pre-set next bit to 1 (Next Trial)
                            // Note: This is non-blocking assignment to next bit, doesn't affect current bit decision
                            sar_reg[bit_ptr - 1] <= 1'b1;
                            phase <= 0; // Return to Phase 0 to wait for new voltage settling
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
    // Directly pass internal register to PHY
    always_comb begin
        dac_p_force = sar_reg;
    end

endmodule
