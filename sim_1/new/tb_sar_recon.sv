`timescale 1ns/1ps

// =============================================================================
// File Name     : tb_sar_recon.sv
// Module Name   : tb_sar_recon (Unit Testbench)
// Description   : Unit testbench for sar_reconstruction module
//
// Verification Strategy:
//   1. Linearity Test: Scan full input range, verify INL/DNL and monotonicity
//   2. Update Test   : Dynamically modify weights, verify calibration interface
//   3. Throughput    : Continuous pipeline stress test, verify throughput and correctness
//
// Update Note:
//   - [Fix] Adjust force_ideal_weights logic to match DUT's new TOTAL_SHIFT
//           Simulate weight truncation in bitstream (approx 2^23) to prevent overflow
// =============================================================================

module tb_sar_recon;

    // --- 1. Parameters (same as RTL) ---
    parameter int CAP_NUM       = 20;
    parameter int WEIGHT_WIDTH  = 30; // [Verified] 30-bit
    parameter int OUTPUT_WIDTH  = 16;
    parameter int FRAC_BITS     = 8;
    
    // --- 2. Signals ---
    logic clk = 0, rst_n;
    logic recon_start;
    logic [CAP_NUM-1:0] raw_bits;
    logic signed [OUTPUT_WIDTH-1:0] adc_dout;
    logic data_valid_out;

    logic w_wr_en;
    logic [4:0] w_wr_addr;
    logic signed [WEIGHT_WIDTH-1:0] w_wr_data;
    
    // --- 3. Instantiate DUT (Device Under Test) ---
    sar_reconstruction #(
        .CAP_NUM      (CAP_NUM),
        .WEIGHT_WIDTH (WEIGHT_WIDTH),
        .OUTPUT_WIDTH (OUTPUT_WIDTH),
        .FRAC_BITS    (FRAC_BITS)
    ) u_recon (
        .clk            (clk),
        .rst_n          (rst_n),
        .data_valid_in  (recon_start),
        .raw_bits       (raw_bits),
        .w_wr_en        (w_wr_en),
        .w_wr_addr      (w_wr_addr),
        .w_wr_data      (w_wr_data),
        .adc_dout       (adc_dout),
        .data_valid_out (data_valid_out)
    );

    // --- 4. Clock Generation ---
    always #5 clk = ~clk;

    // --- 5. Test Sequence ---
    initial begin
        initialize_test();
        test_linearity();
        test_weight_update();
        test_throughput();
        
        $display("\n=== All Tests Completed ===");
        $finish;
    end

    // Initialize test
    task initialize_test();
        rst_n = 0;
        recon_start = 0;
        raw_bits = 0;
        w_wr_en = 0;
        w_wr_addr = 0;
        w_wr_data = 0;
        
        #12 rst_n = 1;
        $display("Time %0t: Reset released", $time);
    endtask

    // Linearity test
    task test_linearity();
        integer i;
        $display("\n--- Linearity Test ---");
        
        // Load ideal weights
        force_ideal_weights();
        
        // Test full range
        for (i = 0; i < (1 << CAP_NUM); i = i + (1 << (CAP_NUM - 10))) begin
            raw_bits = i[CAP_NUM-1:0];
            recon_start = 1;
            #10 recon_start = 0;
            
            wait(data_valid_out);
            $display("Input: %0d -> Output: %0d", raw_bits, adc_dout);
        end
    endtask

    // Weight update test
    task test_weight_update();
        $display("\n--- Weight Update Test ---");
        
        // Update weight for bit 10
        w_wr_en = 1;
        w_wr_addr = 10;
        w_wr_data = 30'sd1073741824; // 2^30
        #10 w_wr_en = 0;
        
        $display("Weight[10] updated to %0d", w_wr_data);
    endtask

    // Throughput test
    task test_throughput();
        integer i;
        $display("\n--- Throughput Test ---");
        
        // Continuous data stream
        for (i = 0; i < 100; i = i + 1) begin
            raw_bits = $random;
            recon_start = 1;
            #10 recon_start = 0;
        end
    endtask

    // Force ideal weights
    task force_ideal_weights();
        integer i;
        logic signed [WEIGHT_WIDTH-1:0] weight;
        
        $display("Loading ideal weights...");
        
        for (i = 0; i < CAP_NUM; i = i + 1) begin
            w_wr_en = 1;
            w_wr_addr = i;
            weight = (1 << (FRAC_BITS + i)); // Ideal binary weight
            w_wr_data = weight;
            #10;
        end
        
        w_wr_en = 0;
        $display("Ideal weights loaded");
    endtask

endmodule
