`timescale 1ns/1ps

/**
 * =============================================================================
 * File Name     : tb_gain_comp_check_lsb.sv
 * Description   : SAR ADC Calibration Algorithm Verification Platform (Industrial Standard)
 * 
 * Verification Logic:
 * 1. Manufacture real chip (including Bit0-5 calibration errors, leading to gain error)
 * 2. Wait for RTL calibration to complete, extract hardware calibrated raw weights
 * 3. Calculate system gain compensation factor K = Phy_MSB / Cal_MSB
 * 4. Apply compensation K to calibrated values (compensating for process variations)
 * 5. Calculate final absolute residue error (in LSB)
 * 6. Criterion: If residue error < 0.5 LSB, design is considered PASS
 * 
 * [Update] 2026-03-05: Add automatic file report output to test_reports/ folder
 * =============================================================================
 */

module tb_gain_comp_check_lsb;

    // --- 1. Parameters ---
    parameter int CAP_NUM       = 20;           // Capacitor array bits (Bit 0 ~ 19)
    parameter int WEIGHT_WIDTH  = 30;           // Weight bit width (Q18.12)
    parameter int MC_RUNS       = 5;            // Monte Carlo runs
    
    // --- 2. Signals ---
    logic clk = 0;
    logic rst_n;
    logic start_calib, calib_done, calib_mode_en;
    logic comp_out;
    
    // Analog frontend interface
    logic [CAP_NUM-1:0] dac_p_force, dac_n_force;
    
    // Register write interface
    logic w_wr_en;
    logic [4:0] w_wr_addr;
    logic signed [WEIGHT_WIDTH-1:0] w_wr_data;

    // --- 3. Storage ---
    real phy_weights [CAP_NUM];        // "On-chip actual" physical truth values
    real stored_cal_vals [CAP_NUM];    // RTL calibration measured values
    
    // --- 4. DUT Instantiation ---
    sar_calib_ctrl_serial #(
        .CAP_NUM(CAP_NUM), 
        .WEIGHT_WIDTH(WEIGHT_WIDTH), 
        .AVG_LOOPS(32) 
    ) dut (.*);

    // Clock generation: 100MHz
    initial forever #5 clk = ~clk;
    
    // =========================================================================
    // [NEW] File Report: Save 16-bit calibration results to test_reports/ folder
    // =========================================================================
    integer report_file;
    string report_filename;
    initial begin
        $srandom($time);
        report_filename = $sformatf("test_reports/calib_report_%0t.txt", $time);
        report_file = $fopen(report_filename, "w");
        if (report_file == 0) begin
            $display("|  [ERROR]  | Cannot create report file: %s", report_filename);
        end else begin
            $display("|  [INFO]   | Report file created: %s", report_filename);
            // Write report header
            $fdisplay(report_file, "==========================================================================");
            $fdisplay(report_file, "  SAR ADC CALIBRATION VERIFICATION REPORT");
            $fdisplay(report_file, "  Generated: %t", $time);
            $fdisplay(report_file, "  Criterion: Absolute Error < 0.5 LSB");
            $fdisplay(report_file, "==========================================================================");
        end
    end
    
    // Close file at end of simulation
    final begin
        if (report_file != 0) begin
            $fclose(report_file);
            $display("|  [INFO]   | Report file saved: %s", report_filename);
        end
    end

    // --- 5. Analog Frontend Modeling ---
    real OFFSET_VOLTAGE = 5.0; // 5 LSB fixed offset (verify convergence)
    real NOISE_RMS      = 0.5; // 0.5 LSB random noise (verify averaging)
    real vp, vn, v_diff;

    // =========================================================================
    // Function: Chip Manufacturing (Simulate Process Variation)
    // =========================================================================
    function automatic void manufacture_chip(int seed);
        real ideal_vals [CAP_NUM]; 
        real error;
        
        // Initialize random seed to ensure different chips for each run
        $srandom(seed);
        
        // --- Ideal Weight Table (Split-Cap Architecture) ---
        ideal_vals[0]=1; ideal_vals[1]=2; ideal_vals[2]=4; ideal_vals[3]=8; ideal_vals[4]=16; ideal_vals[5]=32;
        ideal_vals[6]=33.53; ideal_vals[7]=67.05; ideal_vals[8]=134.10; ideal_vals[9]=268.20;
        ideal_vals[10]=316.91; ideal_vals[11]=316.91; ideal_vals[12]=633.81; ideal_vals[13]=1267.63; ideal_vals[14]=2535.25;
        ideal_vals[15]=5031.09; ideal_vals[16]=5031.09; ideal_vals[17]=10062.17; ideal_vals[18]=20124.35; ideal_vals[19]=40248.69;

        // --- Generate Capacitor Array Weights with Errors ---
        for(int i=0; i<CAP_NUM; i++) begin
            real base = ideal_vals[i] * 256.0; // Convert to Q18.12 format (1 LSB = 256)
            
            // [Real Chip] Bit 0-5 also have errors, leading to gain error
            // But as long as linearity is good, gain error can be compensated by multiplication
            if(i <= 5) error = $dist_normal(seed, 0, 15) / 10000.0;  // 0.15% error
            else       error = $dist_normal(seed, 0, 300) / 10000.0; // 3.00% error
            
            phy_weights[i] = base * (1.0 + error);
        end
    endfunction

    // =========================================================================
    // Analog Model: Comparator as Model
    // =========================================================================
    always @(posedge clk) begin
        vp = 0; vn = 0;
        // Accumulate DAC output signals
        for(int i=0; i<CAP_NUM; i++) begin
            if (dac_p_force[i]) vp += phy_weights[i];
            if (dac_n_force[i]) vn += phy_weights[i];
        end
        
        // Vdiff = (Vp - Vn) + Offset + Noise
        v_diff = vp - vn + OFFSET_VOLTAGE*256.0 + ($dist_normal($time,0,100)/100.0)*NOISE_RMS*256.0;
        
        // Comparator decision
        comp_out <= (v_diff > 0);
    end

    // =========================================================================
    // Capture Logic: Capture RTL Calibration Values
    // =========================================================================
    always @(posedge clk) begin
        if (w_wr_en) begin
            stored_cal_vals[w_wr_addr] = real'(w_wr_data);
        end
    end

    // =========================================================================
    // Testbench Main (Task Function)
    // =========================================================================
    initial begin
        // Variable declarations (cannot be placed in initial blocks due to tool compatibility)
        real gain_factor;
        real restored_val;
        real abs_err_lsb;
        real max_abs_err_lsb;
        real display_phy, display_restored;
        int run_idx, i;
        
        // --- [Acceptance Standard] ---
        // Integral Non-Linearity (INL), for 16-bit ADC typically < 0.5 LSB
        real ABS_ERR_LIMIT = 0.5; 
        
        // Write test configuration to report
        if (report_file != 0) begin
            $fdisplay(report_file, "\nTest Configuration:");
            $fdisplay(report_file, "  CAP_NUM: %0d", CAP_NUM);
            $fdisplay(report_file, "  MC_RUNS: %0d", MC_RUNS);
            $fdisplay(report_file, "  ABS_ERR_LIMIT: %.2f LSB", ABS_ERR_LIMIT);
            $fdisplay(report_file, "\n");
        end

        $display("\n==========================================================================");
        $display("  SAR ADC CALIBRATION VERIFICATION (Criterion: Abs Error < %.1f LSB)", ABS_ERR_LIMIT);
        $display("==========================================================================");
        
        for (run_idx=0; run_idx<MC_RUNS; run_idx++) begin
            // 1. Manufacture a new chip (Seed changes with run_idx)
            manufacture_chip(run_idx + 1000); 
            
            // 2. Start calibration
            rst_n = 0; start_calib = 0;
            #50 rst_n = 1; 
            #50 start_calib = 1; 
            #10 start_calib = 0;
            
            // 3. Wait for completion (add delay to ensure last bit is written to RAM)
            wait(calib_done);
            #200;
            
            // 4. Calculate system gain compensation factor K (using MSB)
            // K = Physical Truth Value / Calibrated Value
            // This simulates the system gain calibration by referencing voltage or other means
            gain_factor = phy_weights[19] / stored_cal_vals[19];
            
            $display("\n--- Run %0d Analysis ---", run_idx);
            $display(">> System Gain Compensation Factor (K) : %.6f", gain_factor);
            $display("--------------------------------------------------------------------------");
            $display("Bit | Phy Val(LSB) | Restored(LSB) | Abs Error(LSB) | Status");
            $display("----|--------------|---------------|----------------|--------");
            
            // Write run header to report
            if (report_file != 0) begin
                $fdisplay(report_file, "\n==========================================================================");
                $fdisplay(report_file, "Run %0d Analysis", run_idx);
                $fdisplay(report_file, "==========================================================================");
                $fdisplay(report_file, "System Gain Compensation Factor (K): %.6f", gain_factor);
                $fdisplay(report_file, "--------------------------------------------------------------------------");
                $fdisplay(report_file, "Bit | Phy Val(LSB) | Restored(LSB) | Abs Error(LSB) | Status");
                $fdisplay(report_file, "----|--------------|---------------|----------------|--------");
            end

            max_abs_err_lsb = 0;
            
            // 5. Check each bit (starting from Bit 6 since 0-5 are reference)
            for (i=6; i<CAP_NUM; i++) begin
                // [Compensation Step]: Calibrated value * K
                restored_val = stored_cal_vals[i] * gain_factor;
                
                // [Calculate Error]: (Restored - Physical) / 256.0
                abs_err_lsb = (restored_val - phy_weights[i]) / 256.0;
                
                // Take absolute value
                if (abs_err_lsb < 0) abs_err_lsb = -abs_err_lsb;
                
                // Print detailed information
                display_phy = phy_weights[i]/256.0;
                display_restored = restored_val/256.0;

                $display(" %2d | %12.2f | %13.2f | %12.4f   | %s", 
                         i+1, display_phy, display_restored, abs_err_lsb,
                         (abs_err_lsb < ABS_ERR_LIMIT) ? "PASS" : "BAD");
                
                // Write to report file
                if (report_file != 0) begin
                    $fdisplay(report_file, " %2d | %12.2f | %13.2f | %12.4f   | %s", 
                             i+1, display_phy, display_restored, abs_err_lsb,
                             (abs_err_lsb < ABS_ERR_LIMIT) ? "PASS" : "BAD");
                end
                         
                if (abs_err_lsb > max_abs_err_lsb) max_abs_err_lsb = abs_err_lsb;
            end
            
            $display("--------------------------------------------------------------------------");
            $display("Max Residual INL Error: %.4f LSB", max_abs_err_lsb);
            
            // Write run summary to report
            if (report_file != 0) begin
                $fdisplay(report_file, "--------------------------------------------------------------------------");
                $fdisplay(report_file, "Max Residual INL Error: %.4f LSB", max_abs_err_lsb);
            end
            
            // 6. Final judgment
            if (max_abs_err_lsb < ABS_ERR_LIMIT) begin
                $display("RESULT: PASS (Design is Production Ready)");
                if (report_file != 0) $fdisplay(report_file, "RESULT: PASS (Design is Production Ready)");
            end else begin
                $display("RESULT: FAIL (Linearity Error exceeds %.1f LSB)", ABS_ERR_LIMIT);
                if (report_file != 0) $fdisplay(report_file, "RESULT: FAIL (Linearity Error exceeds %.1f LSB)", ABS_ERR_LIMIT);
            end
            
            #1000;
        end
        
        // Write final summary
        if (report_file != 0) begin
            $fdisplay(report_file, "\n==========================================================================");
            $fdisplay(report_file, "FINAL SUMMARY");
            $fdisplay(report_file, "==========================================================================");
            $fdisplay(report_file, "All %0d MC runs completed", MC_RUNS);
        end
        
        $finish;
    end

endmodule
