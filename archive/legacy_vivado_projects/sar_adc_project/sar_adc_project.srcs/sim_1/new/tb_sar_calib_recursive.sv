`timescale 1ns/1ps

/**
 * =============================================================================
 * 模块名称: tb_sar_calib_full_mc_ref
 * 验证目标: 验证 RTL 是否修复了 Bit 20 的双重计算 Bug
 * 物理模型: "Golden Reference" (基于用户提供的 Split-Cap 系数表)
 * =============================================================================
 */
module tb_sar_calib_full_mc_ref;

    // --- 仿真参数 ---
    parameter int CAP_NUM       = 20;           // Bit 1-20
    parameter int WEIGHT_WIDTH  = 30;           // Q18.12
    parameter int MC_RUNS       = 10;            // 跑10次 Monte Carlo
    
    // --- 信号声明 ---
    logic clk = 0;
    logic rst_n;
    logic start_calib, calib_done, calib_mode_en;
    logic comp_out, comp_valid = 1;
    
    logic [CAP_NUM-1:0] dac_p_force, dac_n_force;
    logic w_wr_en;
    logic [4:0] w_wr_addr;
    logic signed [WEIGHT_WIDTH-1:0] w_wr_data;

    // --- 物理模型存储 ---
    real phy_weights [CAP_NUM];
    
    // --- 模拟参数 ---
    real OFFSET_VOLTAGE = 5.0;  // 5 LSB
    real NOISE_RMS      = 0.5;  // 0.5 LSB (低噪声以验证算法精度)

    // --- DUT 实例化 ---
    sar_calib_ctrl_recu_ref #(
        .CAP_NUM(CAP_NUM), 
        .WEIGHT_WIDTH(WEIGHT_WIDTH), 
        .AVG_LOOPS(32) 
    ) dut (.*);

    initial forever #5 clk = ~clk;

    // =========================================================================
    // 芯片制造模型 (Golden Table)
    // =========================================================================
    function automatic void manufacture_chip(int seed);
        real ideal_vals [CAP_NUM]; 
        real error;
        $srandom(seed);
        
        $display("\n--- Manufacturing Chip (Seed: %0d) ---", seed);
        
        // [Golden Reference] 严格照抄您的表格
        ideal_vals[0] = 1.00;   ideal_vals[1] = 2.00;
        ideal_vals[2] = 4.00;   ideal_vals[3] = 8.00;
        ideal_vals[4] = 16.00;  ideal_vals[5] = 32.00;
        
        ideal_vals[6] = 33.53;  ideal_vals[7] = 67.05;
        ideal_vals[8] = 134.10; ideal_vals[9] = 268.20;
        
        ideal_vals[10] = 316.91; ideal_vals[11] = 316.91;
        ideal_vals[12] = 633.81; ideal_vals[13] = 1267.63;
        ideal_vals[14] = 2535.25;
        
        ideal_vals[15] = 5031.09; ideal_vals[16] = 5031.09;
        ideal_vals[17] = 10062.17; ideal_vals[18] = 20124.35;
        ideal_vals[19] = 40248.69; // Bit 20 目标值

        for(int i=0; i<CAP_NUM; i++) begin
            automatic real base_val = ideal_vals[i] * 256.0; 
            
            // 误差模型: LSB 0.1%, MSB 3.0%
            if (i <= 5) error = $dist_normal(seed, 0, 10)  / 10000.0; 
            else        error = $dist_normal(seed, 0, 300) / 10000.0;
            
            phy_weights[i] = base_val * (1.0 + error);
        end
    endfunction

    // =========================================================================
    // 模拟比较器
    // =========================================================================
    real vp, vn, v_diff;
    always @(posedge clk) begin
        vp = 0; vn = 0;
        for(int i=0; i<CAP_NUM; i++) begin
            if (dac_p_force[i]) vp += phy_weights[i];
            if (dac_n_force[i]) vn += phy_weights[i];
        end
        v_diff = vp - vn + OFFSET_VOLTAGE*256.0;
        v_diff += ($dist_normal($time, 0, 100)/100.0) * NOISE_RMS * 256.0;

        if (v_diff > 0) comp_out <= 1; 
        else comp_out <= 0;
    end

    // =========================================================================
    // 结果检查 (归一化显示 + 误差捕捉)
    // =========================================================================
    real max_err_perc;
    always @(posedge clk) begin
        if (w_wr_en) begin
            automatic real val_cal = real'(w_wr_data);
            automatic real val_phy = phy_weights[w_wr_addr];
            automatic real err_perc = (val_cal - val_phy) / val_phy * 100.0;
            
            if (err_perc < 0) err_perc = -err_perc;

            // [VISUAL] 除以 256.0 以显示表格值
            $display("[CHECK] Bit %2d | Phy: %10.2f | Cal: %10.2f | Err: %5.2f%%", 
                     w_wr_addr + 1, 
                     val_phy / 256.0,   
                     val_cal / 256.0,   
                     err_perc);
            
            if (w_wr_addr > 5 && err_perc > max_err_perc) max_err_perc = err_perc;
        end
    end

    // =========================================================================
    // 主测试脚本
    // =========================================================================
    initial begin
        $display("STARTING SIMULATION (Final Fix Verification)");
        
        for (int run=0; run<MC_RUNS; run++) begin
            manufacture_chip(run + 100);
            max_err_perc = 0;
            
            rst_n = 0; start_calib = 0;
            #50 rst_n = 1;
            #50 start_calib = 1; #10 start_calib = 0;
            
            wait(calib_done);
            
            $display("--- Run %0d Result ---", run);
            $display("Max Error: %.2f%%", max_err_perc);
            
            // 判据：0.3% 以内为优秀 (考虑 0.5LSB 噪声)
            if (max_err_perc < 0.5) $display("STATUS: PASS (Bit 20 Fixed)");
            else $display("STATUS: FAIL (Still buggy)");
            
            #10000;
        end
        $finish;
    end

endmodule