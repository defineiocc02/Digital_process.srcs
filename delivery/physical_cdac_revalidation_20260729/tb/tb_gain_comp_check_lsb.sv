`timescale 1ns/1ps
`default_nettype none

// =============================================================================
// File Name     : tb_gain_comp_check_lsb.sv
// Target        : sar_calib_ctrl_serial
// Purpose       : Monte Carlo verification for the foreground recursive
//                 capacitor bit-weight calibration loop.
// Tool Scope    : Vivado XSIM 2018.3 batch simulation.
// Language      : SystemVerilog testbench; not intended for synthesis.
//
// Design Intent:
//   This TB verifies the foreground calibration controller against a behavioral
//   split-capacitor DAC/comparator environment. It stresses the recursive
//   positive/negative measurement sequence with capacitor mismatch, comparator
//   offset, comparator noise, and final gain compensation.
//
// Verification Scope:
//   1. Generate process-mismatched physical capacitor weights.
//   2. Apply a fixed comparator offset and random comparator noise.
//   3. Run the RTL positive/negative calibration sequence to completion.
//   4. Capture calibrated weights and apply system gain compensation.
//   5. Check the residual bit-weight error from bit 6 through bit 19.
//
// Modeling Assumptions:
//   - The analog CDAC is represented as real-valued capacitor weights in Q8
//     units. This is a calibration-algorithm model, not a transistor-level model.
//   - Comparator offset is static per run; noise is sampled each clock edge.
//   - LSB section bits 0..5 are treated as trusted reference weights.
//   - The MSB weight anchors gain compensation after calibration completes.
//
// Testbench Architecture:
//   - `manufacture_chip` creates deterministic Monte Carlo mismatch from seeds.
//   - The comparator monitor translates DAC force vectors into `comp_out`.
//   - The write monitor captures the DUT's calibrated weight table.
//   - `analyze_run` is the scoreboard and reports residual error in LSB.
//
// Pass Criteria:
//   - Every Monte Carlo run must have max residual error < 0.5 LSB.
//   - Any failing run calls $fatal so batch simulation returns a failing status.
// =============================================================================

module tb_gain_comp_check_lsb;

    // Calibration configuration. Keep these aligned with the RTL parameters and
    // reproduction report so Monte Carlo residuals remain comparable over time.
    localparam int CAP_NUM       = 20;
    localparam int WEIGHT_WIDTH  = 30;
    localparam int MC_RUNS       = 5;
    localparam int AVG_LOOPS     = 32;
    localparam int CLK_PERIOD_NS = 10;
    localparam real ABS_ERR_LIMIT_LSB = 0.5;
    localparam real OFFSET_LSB        = 5.0;
    localparam real NOISE_RMS_LSB     = 0.5;

    // DUT control and comparator interface.
    logic clk = 1'b0;
    logic rst_n;
    logic start_calib;
    logic calib_done;
    logic calib_mode_en;
    logic comp_out;

    logic [CAP_NUM-1:0] dac_p_force;
    logic [CAP_NUM-1:0] dac_n_force;

    // Calibrated weight writeback stream from the DUT.
    logic w_wr_en;
    logic [4:0] w_wr_addr;
    logic signed [WEIGHT_WIDTH-1:0] w_wr_data;

    // Behavioral analog model state and scoreboarding state.
    real phy_weights [CAP_NUM];
    real stored_cal_vals [CAP_NUM];
    real worst_run_error_lsb = 0.0;

    int checks_total = 0;
    int checks_failed = 0;
    int noise_seed = 32'h4c3a_9271;

    sar_calib_ctrl_serial #(
        .CAP_NUM      (CAP_NUM),
        .WEIGHT_WIDTH (WEIGHT_WIDTH),
        .AVG_LOOPS    (AVG_LOOPS)
    ) dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .start_calib   (start_calib),
        .calib_done    (calib_done),
        .calib_mode_en (calib_mode_en),
        .comp_out      (comp_out),
        .dac_p_force   (dac_p_force),
        .dac_n_force   (dac_n_force),
        .w_wr_en       (w_wr_en),
        .w_wr_addr     (w_wr_addr),
        .w_wr_data     (w_wr_data)
    );

    initial forever #(CLK_PERIOD_NS/2) clk = ~clk;

    // Section banners make long Monte Carlo logs navigable without a waveform.
    task automatic print_section(input string title);
        begin
            $display("");
            $display("========================================================================");
            $display("  %s", title);
            $display("========================================================================");
        end
    endtask

    // Centralized checker. A failing calibration point stops simulation
    // immediately so batch regressions cannot hide marginal runs.
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

    // Real-valued absolute value helper used by residual-error scoring.
    function automatic real abs_real(input real value);
        begin
            abs_real = (value < 0.0) ? -value : value;
        end
    endfunction

    // Nominal split-array capacitor weights expressed in LSB units. The non
    // binary values model the split-sampling architecture documented in the
    // reproduction report and are the reference before process mismatch.
    function automatic real ideal_weight_lsb(input int bit_idx);
        begin
            case (bit_idx)
                0:  ideal_weight_lsb = 1.00;
                1:  ideal_weight_lsb = 2.00;
                2:  ideal_weight_lsb = 4.00;
                3:  ideal_weight_lsb = 8.00;
                4:  ideal_weight_lsb = 16.00;
                5:  ideal_weight_lsb = 32.00;
                6:  ideal_weight_lsb = 33.53;
                7:  ideal_weight_lsb = 67.05;
                8:  ideal_weight_lsb = 134.10;
                9:  ideal_weight_lsb = 268.20;
                10: ideal_weight_lsb = 316.91;
                11: ideal_weight_lsb = 316.91;
                12: ideal_weight_lsb = 633.81;
                13: ideal_weight_lsb = 1267.63;
                14: ideal_weight_lsb = 2535.25;
                15: ideal_weight_lsb = 5031.09;
                16: ideal_weight_lsb = 5031.09;
                17: ideal_weight_lsb = 10062.17;
                18: ideal_weight_lsb = 20124.35;
                default: ideal_weight_lsb = 40248.69;
            endcase
        end
    endfunction

    // Clear captured DUT writeback values before every Monte Carlo run.
    task automatic clear_measurements();
        begin
            for (int i = 0; i < CAP_NUM; i++) begin
                stored_cal_vals[i] = 0.0;
            end
        end
    endtask

    // Build one deterministic virtual chip. Seeds are explicit so failures are
    // reproducible and a problematic run can be replayed exactly.
    task automatic manufacture_chip(input int seed_in);
        int local_seed;
        real base_q;
        real mismatch;
        begin
            local_seed = seed_in;
            for (int i = 0; i < CAP_NUM; i++) begin
                base_q = ideal_weight_lsb(i) * 256.0;

                if (i <= 5)
                    mismatch = $dist_normal(local_seed, 0, 15) / 10000.0;
                else
                    mismatch = $dist_normal(local_seed, 0, 300) / 10000.0;

                phy_weights[i] = base_q * (1.0 + mismatch);
            end
        end
    endtask

    // Apply reset and issue the one-cycle foreground calibration command.
    task automatic reset_and_start_calibration();
        begin
            rst_n = 1'b0;
            start_calib = 1'b0;
            repeat (5) @(negedge clk);
            rst_n = 1'b1;
            repeat (5) @(negedge clk);
            start_calib = 1'b1;
            @(negedge clk);
            start_calib = 1'b0;
        end
    endtask

    // Watchdog-protected completion wait. The high timeout covers the recursive
    // averaging loop while still catching controller deadlocks.
    task automatic wait_for_calibration_done(output bit success);
        int timeout;
        begin
            success = 1'b0;
            for (timeout = 0; timeout < 2_000_000; timeout++) begin
                @(posedge clk);
                if (calib_done === 1'b1) begin
                    success = 1'b1;
                    break;
                end
            end
        end
    endtask

    // Comparator behavioral model. It is clocked to match the digital controller
    // sampling cadence and includes static offset plus per-cycle Gaussian noise.
    always_ff @(posedge clk or negedge rst_n) begin
        real vp;
        real vn;
        real noise_q;

        if (!rst_n) begin
            comp_out <= 1'b0;
        end else begin
            vp = 0.0;
            vn = 0.0;
            for (int i = 0; i < CAP_NUM; i++) begin
                if (dac_p_force[i]) vp += phy_weights[i];
                if (dac_n_force[i]) vn += phy_weights[i];
            end

            noise_q = ($dist_normal(noise_seed, 0, 100) / 100.0) * NOISE_RMS_LSB * 256.0;
            comp_out <= ((vp - vn) + (OFFSET_LSB * 256.0) + noise_q) > 0.0;
        end
    end

    // Capture the calibrated weight table exactly as the reconstruction block
    // would receive it through the shared writeback interface.
    always_ff @(posedge clk) begin
        if (w_wr_en) begin
            stored_cal_vals[w_wr_addr] = real'(w_wr_data);
        end
    end

    // Apply MSB-anchored gain compensation and score every calibrated bit in
    // physical LSB units. Bits 6..19 are checked because bits 0..5 form the
    // trusted LSB reference section in this model.
    task automatic analyze_run(input int run_idx, output real max_abs_err_lsb);
        real gain_factor;
        real restored_val;
        real abs_err_lsb;
        begin
            gain_factor = phy_weights[19] / stored_cal_vals[19];
            max_abs_err_lsb = 0.0;

            $display("");
            $display("Run %0d gain compensation K = %.8f", run_idx, gain_factor);
            $display(" Bit | Physical(LSB) | Restored(LSB) | AbsErr(LSB) | Result");
            $display("-----|---------------|---------------|-------------|--------");

            for (int i = 6; i < CAP_NUM; i++) begin
                restored_val = stored_cal_vals[i] * gain_factor;
                abs_err_lsb = abs_real(restored_val - phy_weights[i]) / 256.0;
                if (abs_err_lsb > max_abs_err_lsb) max_abs_err_lsb = abs_err_lsb;

                $display(" %3d | %13.2f | %13.2f | %11.4f | %s",
                         i + 1,
                         phy_weights[i] / 256.0,
                         restored_val / 256.0,
                         abs_err_lsb,
                         (abs_err_lsb < ABS_ERR_LIMIT_LSB) ? "PASS" : "FAIL");
            end

            $display("Run %0d max residual error = %.4f LSB", run_idx, max_abs_err_lsb);
        end
    endtask

    initial begin
        bit done_ok;
        real max_abs_err_lsb;

        print_section("SAR CALIBRATION MONTE CARLO TESTBENCH START");
        $display("MC_RUNS=%0d AVG_LOOPS=%0d OFFSET=%.2f LSB NOISE_RMS=%.2f LSB LIMIT=%.2f LSB",
                 MC_RUNS, AVG_LOOPS, OFFSET_LSB, NOISE_RMS_LSB, ABS_ERR_LIMIT_LSB);

        clear_measurements();
        rst_n = 1'b0;
        start_calib = 1'b0;

        for (int run_idx = 0; run_idx < MC_RUNS; run_idx++) begin
            print_section($sformatf("MONTE CARLO RUN %0d", run_idx));
            clear_measurements();
            manufacture_chip(1000 + run_idx);
            reset_and_start_calibration();
            wait_for_calibration_done(done_ok);
            record_check(done_ok, $sformatf("calibration completed for run %0d", run_idx));

            repeat (20) @(posedge clk);
            analyze_run(run_idx, max_abs_err_lsb);
            if (max_abs_err_lsb > worst_run_error_lsb) worst_run_error_lsb = max_abs_err_lsb;
            record_check(max_abs_err_lsb < ABS_ERR_LIMIT_LSB,
                         $sformatf("run %0d residual error %.4f LSB below %.2f LSB",
                                   run_idx, max_abs_err_lsb, ABS_ERR_LIMIT_LSB));
        end

        print_section("SAR CALIBRATION TESTBENCH SUMMARY");
        $display("Worst residual error: %.4f LSB", worst_run_error_lsb);
        $display("Checks total        : %0d", checks_total);
        $display("Checks failed       : %0d", checks_failed);
        record_check(checks_failed == 0, "all calibration checks passed");
        $display("OVERALL RESULT : PASS");
        $finish;
    end

endmodule

`default_nettype wire
