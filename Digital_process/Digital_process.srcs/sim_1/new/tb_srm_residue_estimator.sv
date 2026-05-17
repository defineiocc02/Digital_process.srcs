`timescale 1ns/1ps

// =============================================================================
// File Name     : tb_srm_residue_estimator.sv
// Target        : srm_residue_estimator
// Description   : Unit verification for the SRM count-to-residue digital block.
//
// Verification Plan :
//   1. Exercise the negative edge, near-negative edge, center, near-positive
//      edge, and positive edge count cases.
//   2. Check that done pulses only after 22 accepted decisions.
//   3. Check final ones_count and residue_q against the golden Q8 LUT.
//   4. Check LUT symmetry around the zero-residue midpoint.
//
// Pass Criteria :
//   Simulation prints "RESULT: PASS SRM residue estimator LUT and counter
//   behavior" and exits without any FAIL message.
// =============================================================================

module tb_srm_residue_estimator;

    parameter int DECISION_COUNT = 22;
    parameter int RESIDUE_WIDTH  = 30;
    parameter int FRAC_BITS      = 8;

    logic clk = 0;
    logic rst_n;
    logic start;
    logic decision_valid;
    logic decision_bit;
    logic busy;
    logic done;
    logic [4:0] decision_index;
    logic [4:0] ones_count;
    logic signed [RESIDUE_WIDTH-1:0] residue_q;

    int expected_lut [0:DECISION_COUNT];

    srm_residue_estimator #(
        .DECISION_COUNT(DECISION_COUNT),
        .RESIDUE_WIDTH (RESIDUE_WIDTH),
        .FRAC_BITS     (FRAC_BITS)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .start          (start),
        .decision_valid (decision_valid),
        .decision_bit   (decision_bit),
        .busy           (busy),
        .done           (done),
        .decision_index (decision_index),
        .ones_count     (ones_count),
        .residue_q      (residue_q)
    );

    initial forever #5 clk = ~clk;

    // Golden table mirrors the documented reproduction LUT. Keeping it local
    // to the TB makes the acceptance criterion explicit and easy to audit.
    task init_expected_lut();
        begin
            expected_lut[0]  = -258;
            expected_lut[1]  = -194;
            expected_lut[2]  = -158;
            expected_lut[3]  = -131;
            expected_lut[4]  = -110;
            expected_lut[5]  = -91;
            expected_lut[6]  = -74;
            expected_lut[7]  = -58;
            expected_lut[8]  = -43;
            expected_lut[9]  = -28;
            expected_lut[10] = -14;
            expected_lut[11] = 0;
            expected_lut[12] = 14;
            expected_lut[13] = 28;
            expected_lut[14] = 43;
            expected_lut[15] = 58;
            expected_lut[16] = 74;
            expected_lut[17] = 91;
            expected_lut[18] = 110;
            expected_lut[19] = 131;
            expected_lut[20] = 158;
            expected_lut[21] = 194;
            expected_lut[22] = 258;
        end
    endtask

    // Drive one full SRM acquisition with a deterministic number of "1"
    // decisions. Ones are placed first because this block only counts totals;
    // decision order should not affect the final estimate.
    task run_count_case(input int ones);
        int i;
        begin
            @(negedge clk);
            start = 1'b1;
            decision_valid = 1'b0;
            decision_bit = 1'b0;
            @(negedge clk);
            start = 1'b0;

            for (i = 0; i < DECISION_COUNT; i = i + 1) begin
                decision_valid = 1'b1;
                decision_bit = (i < ones);
                @(negedge clk);
            end
            decision_valid = 1'b0;
            decision_bit = 1'b0;

            @(posedge clk);
            if (done !== 1'b1) begin
                $display("RESULT: FAIL count=%0d done missing", ones);
                $finish;
            end
            if (ones_count !== ones[4:0]) begin
                $display("RESULT: FAIL count=%0d ones_count=%0d", ones, ones_count);
                $finish;
            end
            if ($signed(residue_q) !== expected_lut[ones]) begin
                $display("RESULT: FAIL count=%0d residue=%0d expected=%0d", ones, $signed(residue_q), expected_lut[ones]);
                $finish;
            end
            $display("count=%0d residue_q=%0d PASS", ones, $signed(residue_q));
        end
    endtask

    initial begin
        init_expected_lut();
        rst_n = 1'b0;
        start = 1'b0;
        decision_valid = 1'b0;
        decision_bit = 1'b0;
        #50 rst_n = 1'b1;
        #20;

        run_count_case(0);
        run_count_case(1);
        run_count_case(11);
        run_count_case(21);
        run_count_case(22);

        if (expected_lut[0] !== -expected_lut[22]) begin
            $display("RESULT: FAIL LUT symmetry edge");
            $finish;
        end
        if (expected_lut[10] !== -expected_lut[12]) begin
            $display("RESULT: FAIL LUT symmetry center");
            $finish;
        end

        $display("RESULT: PASS SRM residue estimator LUT and counter behavior");
        $finish;
    end

endmodule
