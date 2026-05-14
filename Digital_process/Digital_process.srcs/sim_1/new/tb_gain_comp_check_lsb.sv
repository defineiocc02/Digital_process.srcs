`timescale 1ns/1ps

/**
 * =============================================================================
 * File Name     : tb_gain_comp_check_lsb.sv
 * Description   : SAR ADC Calibration Algorithm Verification Platform (Production Standard)
 * Verification Logic:
 * 1. Simulate real chip manufacturing process (introducing baseline error for Bit0-5 will cause overall gain drift)
 * 2. Wait for RTL calibration to complete, capture hardware-calibrated raw weights (Raw Calibrated Weights)
 * 3. Calculate system gain compensation factor K = Phy_MSB / Cal_MSB
 * 4. Apply calibrated values multiplied by K (simulate post-processing in digital domain)
 * 5. Calculate final absolute residual error (Absolute Residue Error in LSB)
 * 6. Criterion: As long as residual error < 0.5 LSB, considered PASS
 * =============================================================================
 */

module tb_gain_comp_check_lsb;

    // --- 1. Parameter Definition ---
    parameter int CAP_NUM       = 20;           // Capacitor bit count (Bit 0 ~ 19)
    parameter int WEIGHT_WIDTH  = 30;           // Weight bit width (Q18.12)
    parameter int MC_RUNS       = 5;            // Monte Carlo run count
    
    // --- 2. Signal Declaration ---
    logic clk = 0;
    logic rst_n;
    logic start_calib, calib_done, calib_mode_en;
    logic comp_out;
    
    // Analog front-end interface
    logic [CAP_NUM-1:0] dac_p_force, dac_n_force;
    
    // Register write-back interface
    logic w_wr_en;
    logic [4:0] w_wr_addr;
    logic signed [WEIGHT_WIDTH-1:0] w_wr_data;

    // --- 3. Storage Arrays ---
    real phy_weights [CAP_NUM];      // "Physical Truth" actual capacitor values
    real stored_cal_vals [CAP_NUM];  // RTL calibration measured values
    
    // --- 4. DUT Instance (Device Under Test) ---
    // Ensure using the correct intermediate version with serial accumulation
    sar_calib_ctrl_serial #(
        .CAP_NUM(CAP_NUM), 
        .WEIGHT_WIDTH(WEIGHT_WIDTH), 
        .AVG_LOOPS(32) 
    ) dut (.*);

    // Clock generation: 100MHz
    initial forever #5 clk = ~clk;

    // --- 5. Analog Model Parameters ---
    real OFFSET_VOLTAGE = 5.0; // 5 LSB fixed offset (used to verify offset cancellation logic)
    real NOISE_RMS      = 0.5; // 0.5 LSB random noise (used to verify averaging logic)
    real vp, vn, v_diff;

    // =========================================================================
    // Function: Chip Manufacturing (Simulate Process Variation)
    // =========================================================================
    function automatic void manufacture_chip(int seed);
        real ideal_vals [CAP_NUM]; 
        real error;
        
        // Set random seed to ensure each Run has different chip instance
        $srandom(seed);
        
        // --- Ideal weight table (based on Split-Cap structure) ---
        ideal_vals[0]=1; ideal_vals[1]=2; ideal_vals[2]=4; ideal_vals[3]=8; ideal_vals[4]=16; ideal_vals[5]=32;
        ideal_vals[6]=33.53; ideal_vals[7]=67.05; ideal_vals[8]=134.10; ideal_vals[9]=268.20;
        ideal_vals[10]=316.91; ideal_vals[11]=316.91; ideal_vals[12]=633.81; ideal_vals[13]=1267.63; ideal_vals[14]=2535.25;
        ideal_vals[15]=5031.09; ideal_vals[16]=5031.09; ideal_vals[17]=10062.17; ideal_vals[18]=20124.35; ideal_vals[19]=40248.69;

        // --- Generate capacitor weights with process variation ---
        for(int i=0; i<CAP_NUM; i++) begin
            real base = ideal_vals[i] * 256.0; // Convert to Q18.12 fixed-point (1 LSB = 256)
            
            // [Realistic Simulation] Bit 0-5 also have errors, will cause overall gain error
            // But as long as linearity is maintained, calibration can pass through gain compensation
            if(i <= 5) error = $dist_normal(seed, 0, 15) / 10000.0;  // 0.15% deviation
            else       error = $dist_normal(seed, 0, 300) / 10000.0; // 3.00% deviation
            
            phy_weights[i] = base * (1.0 + error);
        end
    endfunction

    // =========================================================================
    // Analog Module: Comparator Behavior Model
    // =========================================================================
    always @(posedge clk) begin
        vp = 0; vn = 0;
        // Accumulate DAC control signals
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
    // Monitor Logic: Capture RTL Output Calibration Values
    // =========================================================================
    always @(posedge clk) begin
        if (w_wr_en) begin
            stored_cal_vals[w_wr_addr] = real'(w_wr_data);
        end
    end

    // =========================================================================
    // Main Test Process (Entry Point)
    // =========================================================================
    initial begin
        // Local variables (must be declared at top of initial block in Verilog)
        real gain_factor;
        real restored_val;
        real abs_err_lsb;
        real max_abs_err_lsb;
        real display_phy, display_restored;
        int run_idx, i;
        
        // --- [Pass Criterion] ---
        // For integral nonlinearity (INL), typical 16-bit ADC needs < 0.5 LSB
        real ABS_ERR_LIMIT = 0.5; 

        $display("\n==========================================================================");
        $display("  SAR ADC CALIBRATION VERIFICATION (Criterion: Abs Error < %.1f LSB)", ABS_ERR_LIMIT);
        $display("==========================================================================");
        
        for (run_idx=0; run_idx<MC_RUNS; run_idx++) begin
            // 1. Manufacture a chip (Seed varies with run_idx)
            manufacture_chip(run_idx + 1000); 
            
            // 2. Start calibration
            rst_n = 0; start_calib = 0;
            #50 rst_n = 1; 
            #50 start_calib = 1; 
            #10 start_calib = 0;
            
            // 3. Wait for completion (extra delay ensures last bit written to RAM)
            wait(calib_done);
            #200;
            
            // 4. Calculate system gain compensation factor K (based on MSB)
            // K = Physical Truth Value / Measured Value
            // In a real system, this is usually determined by reference voltage or production calibration
            gain_factor = phy_weights[19] / stored_cal_vals[19];
            
            $display("\n--- Run %0d Analysis ---", run_idx);
            $display(">> System Gain Compensation Factor (K) : %.6f", gain_factor);
            $display("--------------------------------------------------------------------------");
            $display("Bit | Phy Val(LSB) | Restored(LSB) | Abs Error(LSB) | Status");
            $display("----|--------------|---------------|----------------|--------");

            max_abs_err_lsb = 0;
            
            // 5. Bit-by-bit verification (start from Bit 6, since 0-5 are baseline)
            for (i=6; i<CAP_NUM; i++) begin
                // [Simulate Post-Processing]: Measured Value * K
                restored_val = stored_cal_vals[i] * gain_factor;
                
                // [Calculate Residual Error]: (Restored - Truth) / 256.0
                abs_err_lsb = (restored_val - phy_weights[i]) / 256.0;
                
                // Take absolute value
                if (abs_err_lsb < 0) abs_err_lsb = -abs_err_lsb;
                
                // Print result info
                display_phy = phy_weights[i]/256.0;
                display_restored = restored_val/256.0;

                $display(" %2d | %12.2f | %13.2f | %12.4f   | %s", 
                         i+1, display_phy, display_restored, abs_err_lsb,
                         (abs_err_lsb < ABS_ERR_LIMIT) ? "PASS" : "BAD");
                         
                if (abs_err_lsb > max_abs_err_lsb) max_abs_err_lsb = abs_err_lsb;
            end
            
            $display("--------------------------------------------------------------------------");
            $display("Max Residual INL Error: %.4f LSB", max_abs_err_lsb);
            
            // 6. Final decision
            if (max_abs_err_lsb < ABS_ERR_LIMIT) begin
                $display("RESULT: PASS (Design is Production Ready)");
            end else begin
                $display("RESULT: FAIL (Linearity Error exceeds %.1f LSB)", ABS_ERR_LIMIT);
            end
            
            #1000;
        end
        $finish;
    end

endmodule
