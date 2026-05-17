`timescale 1ns/1ps

// =============================================================================
// Module Name   : srm_residue_estimator
// Description   : Statistical residue measurement (SRM) digital estimator.
//
// Functionality :
//   Counts 22 repeated noisy comparator decisions and maps the observed
//   probability to a signed residue correction using a fixed normal-inverse LUT.
//   The LUT assumes sigma = 0.5 LSB and Q(FRAC_BITS) output scaling.
//
// Notes :
//   - This is the digital reproduction boundary for Huang's SRM phase.
//   - The analog latch/noise process is modeled by the testbench; this block
//     only implements the on-chip digital count and lookup behavior.
// =============================================================================

module srm_residue_estimator #(
    parameter int DECISION_COUNT = 22,
    parameter int RESIDUE_WIDTH  = 30,
    parameter int FRAC_BITS      = 8
)(
    input  logic                           clk,
    input  logic                           rst_n,
    input  logic                           start,
    input  logic                           decision_valid,
    input  logic                           decision_bit,
    output logic                           busy,
    output logic                           done,
    output logic [4:0]                     decision_index,
    output logic [4:0]                     ones_count,
    output logic signed [RESIDUE_WIDTH-1:0] residue_q
);

    localparam int COUNT_WIDTH = 5;

    function automatic logic signed [RESIDUE_WIDTH-1:0] residue_lut(input logic [COUNT_WIDTH-1:0] count);
        logic signed [15:0] q8_value;
        begin
            case (count)
                5'd0:  q8_value = -16'sd258;
                5'd1:  q8_value = -16'sd194;
                5'd2:  q8_value = -16'sd158;
                5'd3:  q8_value = -16'sd131;
                5'd4:  q8_value = -16'sd110;
                5'd5:  q8_value = -16'sd91;
                5'd6:  q8_value = -16'sd74;
                5'd7:  q8_value = -16'sd58;
                5'd8:  q8_value = -16'sd43;
                5'd9:  q8_value = -16'sd28;
                5'd10: q8_value = -16'sd14;
                5'd11: q8_value = 16'sd0;
                5'd12: q8_value = 16'sd14;
                5'd13: q8_value = 16'sd28;
                5'd14: q8_value = 16'sd43;
                5'd15: q8_value = 16'sd58;
                5'd16: q8_value = 16'sd74;
                5'd17: q8_value = 16'sd91;
                5'd18: q8_value = 16'sd110;
                5'd19: q8_value = 16'sd131;
                5'd20: q8_value = 16'sd158;
                5'd21: q8_value = 16'sd194;
                default: q8_value = 16'sd258;
            endcase
            if (FRAC_BITS >= 8)
                residue_lut = {{(RESIDUE_WIDTH-16){q8_value[15]}}, q8_value} <<< (FRAC_BITS - 8);
            else
                residue_lut = {{(RESIDUE_WIDTH-16){q8_value[15]}}, q8_value} >>> (8 - FRAC_BITS);
        end
    endfunction

    logic [4:0] next_ones_count;

    assign next_ones_count = ones_count + (decision_bit ? 5'd1 : 5'd0);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy           <= 1'b0;
            done           <= 1'b0;
            decision_index <= '0;
            ones_count     <= '0;
            residue_q      <= '0;
        end else begin
            done <= 1'b0;

            if (start) begin
                busy           <= 1'b1;
                decision_index <= '0;
                ones_count     <= '0;
                residue_q      <= '0;
            end else if (busy && decision_valid) begin
                ones_count <= next_ones_count;

                if (decision_index == DECISION_COUNT - 1) begin
                    residue_q      <= residue_lut(next_ones_count);
                    busy           <= 1'b0;
                    done           <= 1'b1;
                    decision_index <= '0;
                end else begin
                    decision_index <= decision_index + 1'b1;
                end
            end
        end
    end

endmodule
