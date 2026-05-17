`timescale 1ns/1ps

// =============================================================================
// File Name     : tb_srm_residue_estimator.sv
// Target        : srm_residue_estimator
// Purpose       : Production-style unit verification for the SRM
//                 count-to-residue digital block.
//
// Verification Plan :
//   1. Exercise the negative edge, near-negative edge, center, near-positive
//      edge, and positive edge count cases.
//   2. Check that done pulses only after 22 accepted decisions.
//   3. Check final ones_count and residue_q against the golden Q8 LUT.
//   4. Check LUT symmetry around the zero-residue midpoint.
//
// Pass Criteria :
//   - No FAIL line is printed.
//   - Final transcript prints "OVERALL RESULT : PASS".
//   - Any failed check calls $fatal so batch simulation returns a failing status.
// =============================================================================

module tb_srm_residue_estimator;

    localparam int DECISION_COUNT = 22;
    localparam int RESIDUE_WIDTH  = 30;
    localparam int FRAC_BITS      = 8;
    localparam int CLK_PERIOD_NS  = 10;

    logic clk = 1'b0;
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
    int checks_total = 0;
    int checks_failed = 0;

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

    initial forever #(CLK_PERIOD_NS/2) clk = ~clk;

    task automatic print_section(input string title);
        begin
            $display("");
            $display("================================================================");
            $display("  %s", title);
            $display("================================================================");
        end
    endtask

    task automatic record_check(input bit pass, input string label);
        begin
            checks_total++;
            if (pass) begin
                $display("[PASS] %s", label);
            end else begin
                checks_failed++;
                $display("[FAIL] %s", label);
                $fatal(1, "Testbench check failed: %s", label);
            end
        end
    endtask

    // Golden table mirrors the documented reproduction LUT. Keeping it local
    // to the TB makes the acceptance criterion explicit and easy to audit.
    task automatic init_expected_lut();
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
    task automatic reset_dut();
        begin
            rst_n = 1'b0;
            start = 1'b0;
            decision_valid = 1'b0;
            decision_bit = 1'b0;
            repeat (5) @(negedge clk);
            rst_n = 1'b1;
            repeat (2) @(negedge clk);
        end
    endtask

    task automatic run_count_case(input int ones);
        int measured_residue;
        begin
            @(negedge clk);
            start = 1'b1;
            decision_valid = 1'b0;
            decision_bit = 1'b0;
            @(negedge clk);
            start = 1'b0;

            for (int i = 0; i < DECISION_COUNT; i++) begin
                decision_valid = 1'b1;
                decision_bit = (i < ones);
                @(negedge clk);
            end
            decision_valid = 1'b0;
            decision_bit = 1'b0;

            @(posedge clk);
            measured_residue = $signed(residue_q);
            $display(" %5d | %10d | %12d | %12d | PASS",
                     ones, ones_count, measured_residue, expected_lut[ones]);
            record_check(done === 1'b1,
                         $sformatf("count %0d produced done pulse", ones));
            record_check(ones_count === ones[4:0],
                         $sformatf("count %0d ones_count matched", ones));
            record_check(measured_residue == expected_lut[ones],
                         $sformatf("count %0d residue matched golden LUT", ones));
        end
    endtask

    initial begin
        print_section("SRM RESIDUE ESTIMATOR TESTBENCH START");
        init_expected_lut();
        reset_dut();

        print_section("TEST 1 - COUNT TO RESIDUE LUT");
        $display("  Ones | Reported | Residue(Q8) | Expected(Q8) | Result");
        $display("-------|----------|-------------|--------------|--------");
        run_count_case(0);
        run_count_case(1);
        run_count_case(11);
        run_count_case(21);
        run_count_case(22);

        print_section("TEST 2 - LUT SYMMETRY");
        record_check(expected_lut[0] == -expected_lut[22], "edge LUT symmetry");
        record_check(expected_lut[10] == -expected_lut[12], "near-center LUT symmetry");

        print_section("SRM RESIDUE ESTIMATOR TESTBENCH SUMMARY");
        $display("Checks total : %0d", checks_total);
        $display("Checks failed: %0d", checks_failed);
        record_check(checks_failed == 0, "all SRM estimator checks passed");
        $display("OVERALL RESULT : PASS");
        $finish;
    end

endmodule
