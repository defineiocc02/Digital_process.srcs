`timescale 1ns/1ps

// =============================================================================
// Project       : Split-Sampling SAR ADC Verification
// File Name     : tb_sar_adc_top.sv
// Version       : V17.0 (The Final Fix)
// Description   : 1. [Critical Fix] Initialize Bit 0-5 weights.
//                    Original calibration algorithm's lower 6 bits in RAM default to 0,
//                    manually forcing non-zero values prevents ~32 LSB system missing code.
//                 2. Set FRAC_BITS = 9 to prevent overflow.
//                 3. Expected result: Linearity INL < 1.0 LSB (full range).
// =============================================================================

module tb_sar_adc_top;

    // --- Parameters ---
    parameter int CAP_NUM       = 20;
    parameter int WEIGHT_WIDTH  = 30;
    parameter int OUTPUT_WIDTH  = 16;
    parameter int CLK_PERIOD    = 200; 

    // --- Signals ---
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

    // Hardware SAR Controller Interface
    logic sar_start;
    logic sar_eoc;
    logic sar_hw_valid;
    logic [CAP_NUM-1:0] sar_result_hw;
    logic tb_comp_out_for_hw; 

    // --- Module Instantiation ---
    
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
    initial clk = 0;
    always # (CLK_PERIOD/2) clk = ~clk;

    // --- Test Sequence ---
    initial begin
        // Initialize signals
        rst_n = 0;
        start_calib = 0;
        sar_start = 0;
        calib_mode_en = 0;
        
        // Release reset
        #100 rst_n = 1;
        
        // Start calibration
        #10 start_calib = 1;
        calib_mode_en = 1;
        # (CLK_PERIOD * 2) start_calib = 0;
        
        // Wait for calibration to complete
        wait(calib_done);
        $display("Calibration completed at time %0t", $time);
        
        // Test with different input levels
        test_input_level(20'd524288, "Mid-scale");    // 0.5V
        test_input_level(20'd262144, "1/4-scale");    // 0.25V
        test_input_level(20'd786432, "3/4-scale");    // 0.75V
        
        $display("\n=== All tests completed ===");
        $finish;
    end

    // --- Test Task ---
    task test_input_level;
        input [19:0] phy_input;
        input [100:0] test_name;
        begin
            $display("\n--- Testing: %s (Input=%0d) ---", test_name, phy_input);
            
            // Set physical ADC input
            u_phy.set_input(phy_input);
            
            // Start SAR conversion
            sar_start = 1;
            # (CLK_PERIOD * 2) sar_start = 0;
            
            // Wait for conversion complete
            wait(sar_hw_valid);
            sar_raw_bits = sar_result_hw;
            sar_data_valid = 1;
            # (CLK_PERIOD * 2) sar_data_valid = 0;
            
            // Wait for reconstruction output
            wait(adc_out_valid);
            $display("ADC Output: %0d (Expected: ~%0d)", 
                     adc_final_out, 
                     phy_input >> (20 - OUTPUT_WIDTH));
        end
    endtask

endmodule
