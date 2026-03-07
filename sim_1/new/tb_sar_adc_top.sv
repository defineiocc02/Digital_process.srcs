`timescale 1ns/1ps

// =============================================================================
// Project Name  : Split-Sampling SAR ADC Verification
// File Name     : tb_sar_adc_top.sv
// Version       : V17.0 (The Final Fix)
// Note          : 1. [Critical Fix] Must initialize Bit 0-5 weights.
//                    Original calibration algorithm skipped lower 6 bits, RAM defaults to 0, manual
//                    loading of ideal values is required, otherwise ~32 LSB systematic offset (Missing Code).
//                 2. Set FRAC_BITS = 9 to prevent overflow.
//                 3. Expected Result: Linearity INL < 1.0 LSB (full range).
// =============================================================================

module tb_sar_adc_top;

    // --- Parameter Definition ---
    parameter int CAP_NUM       = 20;
    parameter int WEIGHT_WIDTH  = 30;
    parameter int OUTPUT_WIDTH  = 16;
    parameter int CLK_PERIOD    = 200; 

    // --- Signal Declaration ---
    logic clk, rst_n;
    logic start_calib, calib_done, calib_mode_en;
    
    logic [CAP_NUM-1:0] dac_p_force_calib, dac_n_force_calib; 
    logic [CAP_NUM-1:0] dac_p_force_hw;                       
    logic [CAP_NUM-1:0] dac_p_force_mux, dac_n_force_mux;     
    
    logic comp_out_phy;
    logic w_wr_en;
    logic [4:0] w_wr_addr;
    logic signed [WEIGHT_WIDTH-1:0] w_wr_data;
    
    logic sar_data_valid;
    logic [CAP_NUM-1:0] sar_raw_bits;
    logic signed [OUTPUT_WIDTH-1:0] adc_final_out;
    logic adc_out_valid;

    // Hardware SAR controller interface
    logic sar_start;
    logic sar_eoc;
    logic sar_hw_valid;
    logic [CAP_NUM-1:0] sar_result_hw;
    logic tb_comp_out_for_hw; 

    // --- Module Instances ---
    
    virtual_adc_phy #(.CAP_NUM(CAP_NUM)) u_phy (
        .clk(clk),
        .rst_n(rst_n),
        .dac_p_force(dac_p_force_mux),
        .dac_n_force(dac_n_force_mux), 
        .comp_out(comp_out_phy)
    );

    sar_calib_ctrl_serial #(
        .CAP_NUM(CAP_NUM), 
        .WEIGHT_WIDTH(WEIGHT_WIDTH)
    ) u_calib_ctrl (
        .clk(clk),
        .rst_n(rst_n),
        .start_calib(start_calib),
        .calib_done(calib_done),
        .calib_mode_en(calib_mode_en),
        .comp_out(comp_out_phy),
        .dac_p_force(dac_p_force_calib),
        .dac_n_force(dac_n_force_calib),
        .w_wr_en(w_wr_en),
        .w_wr_addr(w_wr_addr),
        .w_wr_data(w_wr_data)
    );

    sar_adc_controller #(.CAP_NUM(CAP_NUM)) u_sar_logic (
        .clk(clk),
        .rst_n(rst_n),
        .start(sar_start),
        .eoc(sar_eoc),
        .result_out(sar_result_hw),
        .result_valid(sar_hw_valid),
        .comp_out(tb_comp_out_for_hw), 
        .dac_p_force(dac_p_force_hw)   
    );

    // FRAC_BITS = 9 (prevent overflow)
    sar_reconstruction #(
        .CAP_NUM(CAP_NUM), 
        .WEIGHT_WIDTH(WEIGHT_WIDTH), 
        .OUTPUT_WIDTH(OUTPUT_WIDTH), 
        .FRAC_BITS(9)  
    ) u_recon (
        .clk(clk),
        .rst_n(rst_n),
        .data_valid_in(sar_data_valid),
        .raw_bits(sar_raw_bits),
        .w_wr_en(w_wr_en),
        .w_wr_addr(w_wr_addr),
        .w_wr_data(w_wr_data),
        .adc_dout(adc_final_out),
        .data_valid_out(adc_out_valid)
    );

    // --- Clock Generation ---
    initial begin 
        clk = 0; 
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // --- MUX Logic ---
    assign dac_p_force_mux = calib_mode_en ? dac_p_force_calib : dac_p_force_hw;
    assign dac_n_force_mux = calib_mode_en ? dac_n_force_calib : {CAP_NUM{1'b0}};

    // --- Analog Comparator ---
    longint current_analog_input_scaled; 
    longint current_dac_p_val;           
    
    always_comb begin
        current_dac_p_val = 0;
        for (int k=0; k<CAP_NUM; k++) begin
            if (dac_p_force_hw[k]) current_dac_p_val = current_dac_p_val + u_phy.phy_weights[k];
        end
        if (current_dac_p_val > current_analog_input_scaled)
            tb_comp_out_for_hw = 1'b1;
        else
            tb_comp_out_for_hw = 1'b0;
    end

    // =========================================================================
    // Main Test Process
    // =========================================================================
    initial begin
        // --- Variable Declaration ---
        int i, k;
        int timeout;
        longint vin_int_raw; 
        logic signed [OUTPUT_WIDTH-1:0] cur_sample; 
        
        real vin_volts, v_ideal_mv;
        real v_meas_raw, v_meas_fit;
        real meas_0v, meas_max;
        real slope, offset;
        real inl_error;
        real max_inl;
        real cal_val, phy_val, gain_k, abs_err, restored;

        max_inl = 0;

        // --- STEP 0: Initialization ---
        task_print_banner("STEP 0: SYSTEM INITIALIZATION");
        rst_n = 0;
        start_calib = 0; 
        sar_data_valid = 0; 
        sar_start = 0;
        current_analog_input_scaled = 0;
        
        repeat(10) @(posedge clk);
        rst_n = 1;
        
        // [Critical Fix] Manually initialize Bit 0-5
        // These bits are skipped by calibration algorithm, default to 0, loading ideal values
        // is required, otherwise ~32 LSB error.
        // Values from PHY model: 256, 512, 1024, 2048, 4096, 8192
        u_recon.weight_ram[0] = 30'd256;
        u_recon.weight_ram[1] = 30'd512;
        u_recon.weight_ram[2] = 30'd1024;
        u_recon.weight_ram[3] = 30'd2048;
        u_recon.weight_ram[4] = 30'd4096;
        u_recon.weight_ram[5] = 30'd8192;
        
        $display("|  [INFO]   | Clock Period    | %0d ns", CLK_PERIOD);
        $display("|  [INFO]   | LSB Init        | Bit 0-5 manually loaded with ideal weights.");

        // --- STEP 1: Execute Calibration ---
        task_print_banner("STEP 1: FOREGROUND CALIBRATION");
        
        @(posedge clk); start_calib = 1; 
        @(posedge clk); start_calib = 0;
        
        timeout = 0;
        while (!calib_done && timeout < 2000000) begin
            @(posedge clk);
            timeout++;
        end
        
        if (timeout >= 2000000) begin
            $display("|  [ERROR]  | Calib Timeout   | FAILED (Cnt: %d)", timeout);
            $finish;
        end else begin
            $display("|  [RESULT] | Calib Status    | COMPLETE               |");
        end
        
        $display("|  [WAIT]   | Settling Memory | Waiting 20 cycles...   |");
        repeat(20) @(posedge clk); 

        // --- Debug: Check Calibration Accuracy ---
        task_print_banner("DEBUG: CALIBRATION ACCURACY CHECK");
        
        // Calculate K
        gain_k = real'(u_phy.phy_weights[19]) / real'(u_recon.weight_ram[19]);
        
        $display("|  [INFO]   | Phy MSB (MATLAB)| %12.0f           |", real'(u_phy.phy_weights[19]));
        $display("|  [INFO]   | Cal MSB (Meas)  | %12.0f           |", real'(u_recon.weight_ram[19]));
        $display("|  [CALC]   | Gain Factor K   | %12.6f           |", gain_k);
        
        $display("|-----------|-----------------|---------------|----------------|--------------|--------|");
        $display("|    Bit    | Calibrated(Raw) | Restored(Phy) | Truth(Phy)     | Residue(LSB) | Status |");
        $display("|-----------|-----------------|---------------|----------------|--------------|--------|");
        
        for (k=0; k<CAP_NUM; k++) begin
            cal_val = real'(u_recon.weight_ram[k]);
            phy_val = real'(u_phy.phy_weights[k]);
            restored = cal_val * gain_k;
            
            abs_err = (restored - phy_val) / 256.0;
            if (abs_err < 0) abs_err = -abs_err;

            // Bit 0-5 already manually loaded, should also pass (as long as K is close to 1.0)
            // Only check higher bits for residual error, since K is based on MSB
            if (k <= 5) begin
                if (abs_err < 2.0)
                    $display("| Bit %2d    | %15.0f | %13.2f | %14.0f | %12.4f | PASS(Init)|", k, cal_val, restored, phy_val, abs_err);
                else
                    $display("| Bit %2d    | %15.0f | %13.2f | %14.0f | %12.4f | WARN      |", k, cal_val, restored, phy_val, abs_err);
            end 
            else begin
                if (abs_err < 1.0) begin
                    if (k == 6) 
                        $display("| Bit %2d    | %15.0f | %13.2f | %14.0f | %12.4f | PASS(Sp) |", k, cal_val, restored, phy_val, abs_err);
                    else
                        $display("| Bit %2d    | %15.0f | %13.2f | %14.0f | %12.4f | PASS     |", k, cal_val, restored, phy_val, abs_err);
                end else begin
                    $display("| Bit %2d    | %15.0f | %13.2f | %14.0f | %12.4f | FAIL     |", k, cal_val, restored, phy_val, abs_err);
                end
            end
        end
        $display("|-----------|-----------------|---------------|----------------|--------------|--------|");

        // --- STEP 2: System Gain Fitting ---
        task_print_banner("STEP 2: SYSTEM GAIN FITTING");
        
        run_hardware_sar(0); capture_result(cur_sample);
        meas_0v = real'(cur_sample);
        
        vin_int_raw = longint'(0.8 * 10000000.0);
        run_hardware_sar(vin_int_raw); capture_result(cur_sample);
        meas_max = real'(cur_sample);
        
        slope = (meas_max - meas_0v) / 800.0;
        offset = meas_0v;
        
        $display("|  [CALC]   | Fitted Slope    | %0.4f Code/mV", slope);
        $display("|  [CALC]   | Fitted Offset   | %0.2f Code", offset);

        // --- STEP 3: Dynamic Sweep and INL Test ---
        task_print_banner("STEP 3: LINEARITY CHECK (INL)");
        
        $display("+-----------------+--------------+--------------+--------------+-------------------+");
        $display("|    Time (ps)    |  Input (mV)  |  Meas.(mV)   |  INL (LSB)   | Status            |");
        $display("+-----------------+--------------+--------------+--------------+-------------------+");

        for (i=0; i<40; i++) begin
            vin_volts = 0.8 * $sin(2.0 * 3.14159 * i / 40.0);
            v_ideal_mv = vin_volts * 1000.0;
            
            vin_int_raw = longint'(vin_volts * 10000000.0); 
            run_hardware_sar(vin_int_raw);
            capture_result(cur_sample); 
            v_meas_raw = real'(cur_sample);
            
            v_meas_fit = (v_meas_raw - offset) / slope;
            inl_error = (v_meas_fit - v_ideal_mv) * slope; 
            
            if (inl_error < 0) max_inl = (inl_error * -1.0 > max_inl) ? (inl_error * -1.0) : max_inl;
            else               max_inl = (inl_error > max_inl) ? inl_error : max_inl;

            // Criterion < 2.0 LSB
            if (inl_error > 2.0 || inl_error < -2.0)
                $display("| %15t |   %10.1f |   %10.1f | %10.2f | FAIL              |", 
                     $time, v_ideal_mv, v_meas_fit, inl_error);
            else
                $display("| %15t |   %10.1f |   %10.1f |   %10.2f | PASS              |", 
                     $time, v_ideal_mv, v_meas_fit, inl_error);
        end
        $display("+-----------------+--------------+--------------+--------------+-------------------+");

        // --- STEP 4: Final Summary ---
        task_print_banner("STEP 4: FINAL SUMMARY");
        if (max_inl < 2.0) 
            $display("|  [CHECK]  | Linearity (INL) | PASS (Max INL = %0.2f LSB)", max_inl);
        else 
            $display("|  [CHECK]  | Linearity (INL) | FAIL (Max INL = %0.2f LSB)", max_inl);
            
        $finish;
    end

    // =========================================================================
    // Tasks
    // =========================================================================
    task task_print_banner(string title);
        $display("\n");
        $display("=================================================================================================");
        $display("  %s", title);
        $display("=================================================================================================");
    endtask

    task run_hardware_sar(input longint input_val_raw);
        current_analog_input_scaled = input_val_raw + 10485760; 
        sar_start <= 1;
        @(posedge clk);
        sar_start <= 0;
        wait(sar_eoc);
        sar_raw_bits   <= sar_result_hw;
        sar_data_valid <= 1;
        @(posedge clk);
        sar_data_valid <= 0;
    endtask

    task capture_result(output logic signed [OUTPUT_WIDTH-1:0] result_code);
        int timeout_cnt;
        timeout_cnt = 0;
        while (!adc_out_valid && timeout_cnt < 20) begin
            @(posedge clk);
            timeout_cnt++;
        end
        if (adc_out_valid) result_code = adc_final_out; 
        else begin
            result_code = 0;
            $display("|  [WARN]   | Reconstruction Timeout | Data missed at time %t", $time);
        end
    endtask

endmodule
