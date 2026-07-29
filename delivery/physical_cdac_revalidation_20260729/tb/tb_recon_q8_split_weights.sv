`timescale 1ns/1ps
`default_nettype none

// =============================================================================
// File Name     : tb_recon_q8_split_weights.sv
// Target        : sar_reconstruction
// Purpose       : Fixed-point contract test for Q8 split-capacitor weights.
// Tool Scope    : Vivado XSIM 2018.3 batch simulation.
// Language      : SystemVerilog testbench; not intended for synthesis.
//
// Design Intent:
//   This TB closes the unit contract that tb_sar_recon_binary_norm intentionally
//   does not cover. It loads split-capacitor ideal weights in the same Q8 unit
//   used by the calibration controller and compares sar_reconstruction against
//   a local bit-exact model of its fixed-point arithmetic.
//
// Verification Scope:
//   1. Load split-cap ideal weights, where 256 represents one output-code LSB.
//   2. Exercise negative full-scale, positive full-scale, sparse, alternating,
//      random, and residue-injected raw decision patterns.
//   3. Compare DUT output against the local manual model at every test point.
//   4. Verify Q8 SRM residue shifts a non-saturated output by signed code steps.
//
// Interface Assumptions:
//   - `w_wr_data` and `weight_ram` share the same signed Q8 unit.
//   - `srm_residue = +256` means +1 output-code LSB before final rounding.
//   - `raw_bits[i] = 1` contributes +W_i; `raw_bits[i] = 0` contributes -W_i.
//   - The DUT's current rounding convention is matched exactly, including the
//     positive half-LSB bias used before arithmetic right shift.
//
// Pass Criteria:
//   - No FAIL line is printed.
//   - Final transcript prints "OVERALL RESULT : PASS".
//   - Any failed check calls $fatal so batch simulation returns a failing status.
// =============================================================================

module tb_recon_q8_split_weights;

    localparam int CAP_NUM       = 20;
    localparam int WEIGHT_WIDTH  = 30;
    localparam int OUTPUT_WIDTH  = 16;
    localparam int FRAC_BITS     = 8;
    localparam int CLK_PERIOD_NS = 10;
    localparam logic signed [WEIGHT_WIDTH-1:0] Q8_ONE_CODE = 30'sd256;

    logic clk = 1'b0;
    logic rst_n;
    logic recon_start;
    logic [CAP_NUM-1:0] raw_bits;
    logic signed [OUTPUT_WIDTH-1:0] adc_dout;
    logic data_valid_out;

    logic w_wr_en;
    logic [4:0] w_wr_addr;
    logic signed [WEIGHT_WIDTH-1:0] w_wr_data;
    logic signed [WEIGHT_WIDTH-1:0] srm_residue;

    logic signed [WEIGHT_WIDTH-1:0] split_weight_q8 [0:CAP_NUM-1];

    int checks_total = 0;
    int checks_failed = 0;

    sar_reconstruction #(
        .CAP_NUM      (CAP_NUM),
        .WEIGHT_WIDTH (WEIGHT_WIDTH),
        .OUTPUT_WIDTH (OUTPUT_WIDTH),
        .FRAC_BITS    (FRAC_BITS)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .data_valid_in  (recon_start),
        .raw_bits       (raw_bits),
        .w_wr_en        (w_wr_en),
        .w_wr_addr      (w_wr_addr),
        .w_wr_data      (w_wr_data),
        .srm_residue    (srm_residue),
        .adc_dout       (adc_dout),
        .data_valid_out (data_valid_out)
    );

    initial forever #(CLK_PERIOD_NS/2) clk = ~clk;

    function automatic logic signed [WEIGHT_WIDTH-1:0] q8_from_lsb(input real value_lsb);
        real scaled;
        int rounded;
        begin
            scaled = value_lsb * real'(1 << FRAC_BITS);
            rounded = $rtoi(scaled + 0.5);
            q8_from_lsb = rounded[WEIGHT_WIDTH-1:0];
        end
    endfunction

    function automatic int manual_reconstruct(
        input logic [CAP_NUM-1:0] bits,
        input logic signed [WEIGHT_WIDTH-1:0] residue_q8
    );
        logic signed [39:0] sum;
        logic signed [39:0] val_div2_residue;
        logic signed [39:0] val_round;
        logic signed [39:0] val_shift;
        begin
            sum = '0;
            for (int i = 0; i < CAP_NUM; i++) begin
                if (bits[i])
                    sum = sum + signed'(40'(split_weight_q8[i]));
                else
                    sum = sum - signed'(40'(split_weight_q8[i]));
            end

            val_div2_residue = (sum >>> 1) + signed'(40'(residue_q8));
            val_round = val_div2_residue + (40'sd1 <<< (FRAC_BITS - 1));
            val_shift = val_round >>> FRAC_BITS;

            if (val_shift > 32767)
                manual_reconstruct = 32767;
            else if (val_shift < -32768)
                manual_reconstruct = -32768;
            else
                manual_reconstruct = int'(val_shift);
        end
    endfunction

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

    task automatic init_split_weight_table();
        begin
            split_weight_q8[0]  = q8_from_lsb(1.00);
            split_weight_q8[1]  = q8_from_lsb(2.00);
            split_weight_q8[2]  = q8_from_lsb(4.00);
            split_weight_q8[3]  = q8_from_lsb(8.00);
            split_weight_q8[4]  = q8_from_lsb(16.00);
            split_weight_q8[5]  = q8_from_lsb(32.00);
            split_weight_q8[6]  = q8_from_lsb(33.53);
            split_weight_q8[7]  = q8_from_lsb(67.05);
            split_weight_q8[8]  = q8_from_lsb(134.10);
            split_weight_q8[9]  = q8_from_lsb(268.20);
            split_weight_q8[10] = q8_from_lsb(316.91);
            split_weight_q8[11] = q8_from_lsb(316.91);
            split_weight_q8[12] = q8_from_lsb(633.81);
            split_weight_q8[13] = q8_from_lsb(1267.63);
            split_weight_q8[14] = q8_from_lsb(2535.25);
            split_weight_q8[15] = q8_from_lsb(5031.09);
            split_weight_q8[16] = q8_from_lsb(5031.09);
            split_weight_q8[17] = q8_from_lsb(10062.17);
            split_weight_q8[18] = q8_from_lsb(20124.35);
            split_weight_q8[19] = q8_from_lsb(40248.69);
        end
    endtask

    task automatic reset_dut();
        begin
            rst_n = 1'b0;
            recon_start = 1'b0;
            raw_bits = '0;
            w_wr_en = 1'b0;
            w_wr_addr = '0;
            w_wr_data = '0;
            srm_residue = '0;
            repeat (5) @(negedge clk);
            rst_n = 1'b1;
            repeat (3) @(negedge clk);
        end
    endtask

    task automatic write_weight(input int index);
        begin
            @(negedge clk);
            w_wr_en   = 1'b1;
            w_wr_addr = index[4:0];
            w_wr_data = split_weight_q8[index];
            @(negedge clk);
            w_wr_en   = 1'b0;
            w_wr_addr = '0;
            w_wr_data = '0;
        end
    endtask

    task automatic load_split_weights();
        begin
            for (int i = 0; i < CAP_NUM; i++) begin
                write_weight(i);
            end
        end
    endtask

    task automatic wait_for_result(output bit success);
        int timeout;
        begin
            success = 1'b0;
            for (timeout = 0; timeout < 20; timeout++) begin
                @(posedge clk);
                if (data_valid_out === 1'b1) begin
                    success = 1'b1;
                    break;
                end
            end
        end
    endtask

    task automatic run_vector(
        input string label,
        input logic [CAP_NUM-1:0] bits,
        input logic signed [WEIGHT_WIDTH-1:0] residue_q8
    );
        bit ok;
        int expected;
        int measured;
        begin
            raw_bits = bits;
            srm_residue = residue_q8;
            expected = manual_reconstruct(bits, residue_q8);

            @(negedge clk);
            recon_start = 1'b1;
            @(negedge clk);
            recon_start = 1'b0;
            wait_for_result(ok);
            record_check(ok, {label, " produced data_valid_out"});

            measured = $signed(adc_dout);
            $display("%-28s raw=%05h residue_q8=%0d expected=%0d measured=%0d",
                     label, bits, residue_q8, expected, measured);
            record_check(measured == expected,
                         $sformatf("%s matched Q8 split-weight manual model", label));
        end
    endtask

    initial begin
        int base_expected;
        int plus_expected;

        $dumpfile("tb_recon_q8_split_weights.vcd");
        $dumpvars(0, tb_recon_q8_split_weights);

        print_section("Q8 SPLIT-WEIGHT RECONSTRUCTION CONTRACT TEST START");
        init_split_weight_table();
        reset_dut();
        load_split_weights();

        print_section("TEST 1 - BIT-EXACT Q8 SPLIT-WEIGHT VECTORS");
        run_vector("negative full-scale", '0, '0);
        run_vector("positive full-scale", '1, '0);
        run_vector("alternating 0x55555", 20'h55555, '0);
        run_vector("alternating 0xaaaaa", 20'haaaaa, '0);
        run_vector("single MSB only", 20'h80000, '0);
        run_vector("deterministic random", 20'h5daf9, '0);

        print_section("TEST 2 - Q8 SRM RESIDUE UNIT CONTRACT");
        base_expected = manual_reconstruct(20'h55555, '0);
        plus_expected = manual_reconstruct(20'h55555, Q8_ONE_CODE);
        record_check((plus_expected - base_expected) == 1,
                     "manual Q8 residue +256 shifts non-saturated code by +1");

        run_vector("residue +1 code", 20'h55555, Q8_ONE_CODE);
        run_vector("residue -1 code", 20'h55555, -Q8_ONE_CODE);

        print_section("Q8 SPLIT-WEIGHT RECONSTRUCTION CONTRACT SUMMARY");
        $display("Checks total : %0d", checks_total);
        $display("Checks failed: %0d", checks_failed);
        record_check(checks_failed == 0, "all Q8 split-weight contract checks passed");
        $display("OVERALL RESULT : PASS");
        $finish;
    end

endmodule

`default_nettype wire
