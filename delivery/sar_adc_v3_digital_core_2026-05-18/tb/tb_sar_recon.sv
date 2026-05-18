`timescale 1ns/1ps
`default_nettype none

// =============================================================================
// File Name     : tb_sar_recon.sv
// Target        : sar_reconstruction
// Purpose       : Production-style unit testbench for the calibrated digital
//                 reconstruction path.
// Tool Scope    : Vivado XSIM 2018.3 batch simulation.
// Language      : SystemVerilog testbench; not intended for synthesis.
//
// Design Intent:
//   This TB verifies the digital reconstruction datapath used after SAR bit
//   decisions and calibration-weight loading. It checks that raw capacitor
//   decisions, calibrated bit weights, and SRM residue correction combine into
//   the expected signed output code.
//
// Verification Scope:
//   1. Ideal linearity sweep over 20 input points.
//   2. Calibration weight write sensitivity.
//   3. Full-rate pipeline valid propagation.
//   4. SRM residue correction injection in the reconstruction fixed-point domain.
//
// Interface Assumptions:
//   - `data_valid_in` is a one-cycle pulse synchronous to `clk`.
//   - `w_wr_en` writes one Q4.4-style reconstruction weight per clock cycle.
//   - `srm_residue` is a signed Q8 correction term applied before output scaling.
//   - The DUT drives `data_valid_out` when `adc_dout` is stable.
//
// Testbench Architecture:
//   - Driver tasks generate resets, weight writes, and sample-valid pulses.
//   - Local golden helpers compute ideal raw decisions and expected output codes.
//   - `record_check` is the single scoreboard gate; every failure calls `$fatal`.
//
// Pass Criteria:
//   - No FAIL line is printed.
//   - Final transcript prints "OVERALL RESULT : PASS".
//   - Any failed check calls $fatal so batch simulation returns a failing status.
// =============================================================================

module tb_sar_recon;

    // Core configuration mirrors the delivered RTL defaults. Keep these values
    // aligned with the DUT instance so the TB remains a direct unit-level signoff
    // check rather than a separate behavioral model.
    localparam int CAP_NUM       = 20;
    localparam int WEIGHT_WIDTH  = 30;
    localparam int OUTPUT_WIDTH  = 16;
    localparam int FRAC_BITS     = 8;
    localparam int CLK_PERIOD_NS = 10;

    // DUT clock/reset and conversion interface.
    logic clk = 1'b0;
    logic rst_n;
    logic recon_start;
    logic [CAP_NUM-1:0] raw_bits;
    logic signed [OUTPUT_WIDTH-1:0] adc_dout;
    logic data_valid_out;

    // Calibration-weight write port and SRM correction input.
    logic w_wr_en;
    logic [4:0] w_wr_addr;
    logic signed [WEIGHT_WIDTH-1:0] w_wr_data;
    logic signed [WEIGHT_WIDTH-1:0] srm_residue;

    // Scoreboard counters are deliberately simple so batch logs can be parsed
    // without opening waveforms.
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

    // Convert a normalized analog input range [-1.0, +1.0] into the raw SAR
    // decision vector expected by the reconstruction block. Saturation keeps
    // randomized or boundary test points inside the representable code space.
    function automatic logic [CAP_NUM-1:0] generate_ideal_bits(input real voltage);
        logic [63:0] full_scale_code;
        real scaled_v;
        real max_code;
        begin
            max_code = real'(longint'(1) << CAP_NUM) - 1.0;
            scaled_v = (voltage + 1.0) * 0.5 * max_code;

            if (scaled_v < 0.0) scaled_v = 0.0;
            if (scaled_v > max_code) scaled_v = max_code;

            full_scale_code = longint'(scaled_v);
            generate_ideal_bits = full_scale_code[CAP_NUM-1:0];
        end
    endfunction

    // Integer absolute value helper used by all code-domain tolerances.
    function automatic int abs_int(input int value);
        begin
            abs_int = (value < 0) ? -value : value;
        end
    endfunction

    // Human-readable section separator. CI parsing only depends on PASS/FAIL
    // lines; this text exists for engineering log review.
    task automatic print_section(input string title);
        begin
            $display("");
            $display("================================================================");
            $display("  %s", title);
            $display("================================================================");
        end
    endtask

    // Centralized checker. A failure immediately terminates simulation so a
    // scripted regression receives a non-zero return path from XSIM.
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

    // Reset all TB-driven inputs to deterministic values before releasing reset.
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

    // Wait for the DUT's result handshake. The timeout protects batch runs from
    // hanging forever if a pipeline-valid bug is introduced later.
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

    // Apply one reconstruction sample using the same one-cycle valid convention
    // expected at the block boundary.
    task automatic drive_sample(input logic [CAP_NUM-1:0] bits, output bit success);
        begin
            raw_bits = bits;
            @(negedge clk);
            recon_start = 1'b1;
            @(negedge clk);
            recon_start = 1'b0;
            wait_for_result(success);
        end
    endtask

    // Load a monotonic ideal weight table. The table is intentionally simple
    // here; calibration non-ideality is covered by tb_gain_comp_check_lsb.
    task automatic load_ideal_weights();
        logic [63:0] calc_w;
        begin
            srm_residue = '0;
            @(negedge clk);
            for (int i = 0; i < CAP_NUM; i++) begin
                w_wr_en   = 1'b1;
                w_wr_addr = i[4:0];
                calc_w    = (longint'(1) << i) << 4;
                w_wr_data = calc_w[WEIGHT_WIDTH-1:0];
                @(negedge clk);
            end
            w_wr_en = 1'b0;
            w_wr_addr = '0;
            w_wr_data = '0;
            @(negedge clk);
        end
    endtask

    // Regression 1: end-to-end code-domain linearity with ideal weights.
    task automatic test_linearity();
        real vin;
        int expected;
        int measured;
        int delta_code;
        bit ok;
        begin
            print_section("TEST 1 - IDEAL LINEARITY SWEEP");
            load_ideal_weights();
            $display("  Pt | Vin(norm) | RawBits | Expected | Measured | Delta | Result");
            $display("-----|-----------|---------|----------|----------|-------|--------");

            for (int i = 0; i < 20; i++) begin
                vin = -0.95 + (i * 1.9 / 19.0);
                expected = int'(vin * 32768.0);

                drive_sample(generate_ideal_bits(vin), ok);
                record_check(ok, $sformatf("linearity point %0d produced data_valid_out", i));

                measured = $signed(adc_dout);
                delta_code = measured - expected;
                if (abs_int(delta_code) <= 1) begin
                    $display(" %3d | %9.4f | %05h   | %8d | %8d | %5d | MATCH",
                             i, vin, raw_bits, expected, measured, delta_code);
                end else begin
                    $display(" %3d | %9.4f | %05h   | %8d | %8d | %5d | DIFF",
                             i, vin, raw_bits, expected, measured, delta_code);
                end
                record_check(abs_int(delta_code) <= 1,
                             $sformatf("linearity point %0d within +/-1 code", i));
            end
        end
    endtask

    // Regression 2: prove the programmable weight memory affects the result.
    task automatic test_weight_update();
        logic [63:0] base_w;
        logic [63:0] err_w;
        int before_update;
        int after_update;
        bit ok;
        begin
            print_section("TEST 2 - CALIBRATION WEIGHT WRITE SENSITIVITY");
            load_ideal_weights();

            drive_sample(longint'(1) << (CAP_NUM - 1), ok);
            record_check(ok, "baseline conversion produced data_valid_out");
            before_update = $signed(adc_dout);

            base_w = (longint'(1) << (CAP_NUM - 1)) << 4;
            err_w  = (base_w * 11) / 10;

            @(negedge clk);
            w_wr_en   = 1'b1;
            w_wr_addr = (CAP_NUM - 1);
            w_wr_data = err_w[WEIGHT_WIDTH-1:0];
            @(negedge clk);
            w_wr_en = 1'b0;

            drive_sample(longint'(1) << (CAP_NUM - 1), ok);
            record_check(ok, "post-update conversion produced data_valid_out");
            after_update = $signed(adc_dout);

            $display("Baseline=%0d  After +10%% MSB weight=%0d  Delta=%0d",
                     before_update, after_update, after_update - before_update);
            record_check(abs_int(after_update - before_update) > 100,
                         "MSB weight update visibly affects reconstruction output");
        end
    endtask

    // Regression 3: issue back-to-back samples and confirm valid propagation.
    task automatic test_pipeline_throughput();
        int rx_count;
        int timeout;
        begin
            print_section("TEST 3 - PIPELINE THROUGHPUT");
            load_ideal_weights();
            rx_count = 0;
            timeout = 0;

            fork
                begin
                    for (int i = 0; i < 5; i++) begin
                        @(negedge clk);
                        raw_bits = $urandom;
                        recon_start = 1'b1;
                        $display("[TX] t=%0t sample=%0d raw=%05h", $time, i + 1, raw_bits);
                    end
                    @(negedge clk);
                    recon_start = 1'b0;
                end

                begin
                    while (rx_count < 5 && timeout < 50) begin
                        @(posedge clk);
                        if (data_valid_out === 1'b1) begin
                            rx_count++;
                            $display("[RX] t=%0t sample=%0d dout=%0d", $time, rx_count, $signed(adc_dout));
                        end
                        timeout++;
                    end
                end
            join

            record_check(rx_count == 5, $sformatf("received all continuous samples, rx_count=%0d", rx_count));
        end
    endtask

    // Regression 4: inject signed SRM Q8 residue terms and check one-code steps.
    task automatic test_srm_residue_injection();
        int zero_code;
        int plus_code;
        int minus_code;
        bit ok;
        begin
            print_section("TEST 4 - SRM RESIDUE INJECTION");
            load_ideal_weights();
            raw_bits = generate_ideal_bits(0.0);

            srm_residue = 0;
            drive_sample(raw_bits, ok);
            record_check(ok, "zero-residue conversion produced data_valid_out");
            zero_code = $signed(adc_dout);

            srm_residue = 256;
            drive_sample(raw_bits, ok);
            record_check(ok, "positive-residue conversion produced data_valid_out");
            plus_code = $signed(adc_dout);

            srm_residue = -256;
            drive_sample(raw_bits, ok);
            record_check(ok, "negative-residue conversion produced data_valid_out");
            minus_code = $signed(adc_dout);

            srm_residue = 0;
            $display("Zero=%0d  Plus(Q8=+256)=%0d  Minus(Q8=-256)=%0d",
                     zero_code, plus_code, minus_code);
            record_check((plus_code - zero_code) == 1 && (zero_code - minus_code) == 1,
                         "SRM Q8 residue shifts final output by signed one-code steps");
        end
    endtask

    initial begin
        $dumpfile("tb_sar_recon.vcd");
        $dumpvars(0, tb_sar_recon);

        print_section("SAR RECONSTRUCTION TESTBENCH START");
        reset_dut();

        test_linearity();
        test_weight_update();
        test_pipeline_throughput();
        test_srm_residue_injection();

        print_section("SAR RECONSTRUCTION TESTBENCH SUMMARY");
        $display("Checks total : %0d", checks_total);
        $display("Checks failed: %0d", checks_failed);
        record_check(checks_failed == 0, "all sar_reconstruction checks passed");
        $display("OVERALL RESULT : PASS");
        $finish;
    end

endmodule

`default_nettype wire
