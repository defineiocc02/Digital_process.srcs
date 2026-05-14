`timescale 1ns/1ps

module tb_sar_calib_sys;

    // --- 仿真参数配置 ---
    parameter int CAP_NUM       = 20;
    parameter int WEIGHT_WIDTH  = 30;
    parameter int FRAC_BITS     = 8;
    parameter int MC_RUNS       = 10; // Monte Carlo 跑 10 次
    
    // --- 物理模型常量 (关键更新) ---
    // 高位失配大，低位失配小，模拟真实硅片特性
    real MSB_MISMATCH_SIGMA  = 0.05;  // Bit 6-19: 5% (恶劣偏差)
    real LSB_MISMATCH_SIGMA  = 0.01;  // Bit 0-5:  1% (高精度尺子)
    
    real NOISE_SIGMA_LSB     = 0.5;   // 系统噪声
    real COMP_OFFSET_LSB     = 1.0;   // 比较器失调

    // --- 信号定义 ---
    logic clk=0, rst_n;
    logic start_calib, calib_done;
    logic comp_out, comp_valid;
    logic calib_mode_en;
    logic [CAP_NUM-1:0] dac_p_force, dac_n_force;
    logic w_wr_en;
    logic [4:0] w_wr_addr;
    logic signed [WEIGHT_WIDTH-1:0] w_wr_data;

    // --- DUT 实例化 (v22.0) ---
    sar_calib_ctrl #(
        .CAP_NUM(CAP_NUM), .WEIGHT_WIDTH(WEIGHT_WIDTH), 
        .COMP_WAIT_CYC(16), .AVG_LOOPS(32), .MAX_CALIB_BIT(5)
    ) dut (.*);

    initial forever #5 clk = ~clk;

    // --- 物理电容阵列模型 ---
    real phy_caps [CAP_NUM];
    real ideal_caps [CAP_NUM];

    // 高斯随机数生成器
    function real get_gaussian(input real sigma);
        real u1 = $urandom_range(1, 2147483647)/2147483647.0;
        real u2 = $urandom_range(1, 2147483647)/2147483647.0;
        return sigma * $sqrt(-2.0*$ln(u1)) * $cos(2.0*3.14159*u2);
    endfunction

    // 芯片制造任务 (分段 Sigma)
    task manufacture_new_chip(input int run_id);
        ideal_caps[0]=1.0;   ideal_caps[1]=2.0;   ideal_caps[2]=4.0;
        ideal_caps[3]=8.0;   ideal_caps[4]=16.0;  ideal_caps[5]=32.0;
        ideal_caps[6]=33.53; 
        ideal_caps[7]=67.05;    ideal_caps[8]=134.10;
        ideal_caps[9]=268.20;   ideal_caps[10]=316.91;  
        ideal_caps[11]=316.91;  ideal_caps[12]=633.81;  
        ideal_caps[13]=1267.63; ideal_caps[14]=2535.25; 
        ideal_caps[15]=5031.09; ideal_caps[16]=5031.09; 
        ideal_caps[17]=10062.17;ideal_caps[18]=20124.35;
        ideal_caps[19]=40248.69;

        $display("\n--- Chip %0d Manufactured ---", run_id);
        for(int i=0; i<CAP_NUM; i++) begin
            real mismatch;
            // [关键]: 低位用小误差，高位用大误差
            if (i <= 5) mismatch = get_gaussian(LSB_MISMATCH_SIGMA);
            else        mismatch = get_gaussian(MSB_MISMATCH_SIGMA);
            
            phy_caps[i] = ideal_caps[i] * (1.0 + mismatch);
        end
    endtask

    // --- AFE 模拟前端模型 ---
    real vp, vn, noise_val;
    always @(posedge clk) begin
        if (calib_mode_en) begin
            vp = 0; vn = 0;
            // 根据 DAC Force 信号累加物理电容值
            for(int i=0; i<CAP_NUM; i++) begin
                if(dac_p_force[i]) vp += phy_caps[i];
                if(dac_n_force[i]) vn += phy_caps[i];
            end
            
            // 注入噪声
            noise_val = get_gaussian(NOISE_SIGMA_LSB);
            
            // 比较器判决
            if ((vp - vn + noise_val + COMP_OFFSET_LSB) > 0) comp_out <= 1;
            else comp_out <= 0;
            
            comp_valid <= 1;
        end else begin
            comp_valid <= 0;
        end
    end

    // --- 结果统计记录 ---
    real ratio_history [MC_RUNS][CAP_NUM];
    int run_idx;
    
    task record_result(input int run, input int bit_idx, input real calib, input real phy);
        ratio_history[run][bit_idx] = calib / phy;
    endtask

    always @(posedge clk) begin
        if (w_wr_en) begin
            real c_val = real'(w_wr_data) / 256.0;
            record_result(run_idx, w_wr_addr, c_val, phy_caps[w_wr_addr]);
            $display("Bit %2d | Phy: %9.2f | Calib: %9.2f | Err: %+.3f", 
                     w_wr_addr, phy_caps[w_wr_addr], c_val, c_val - phy_caps[w_wr_addr]);
        end
    end

    // --- 主测试流程 ---
    initial begin
        $display("=== SAR Calibration Monte Carlo (Architecture: Sub-SAR v22.0) ===");
        $display("Config: Noise=%.2f LSB, Runs=%0d", NOISE_SIGMA_LSB, MC_RUNS);
        $display("Mismatch: LSB=%.1f%%, MSB=%.1f%%", LSB_MISMATCH_SIGMA*100, MSB_MISMATCH_SIGMA*100);
        
        for (run_idx = 0; run_idx < MC_RUNS; run_idx++) begin
            manufacture_new_chip(run_idx);
            rst_n = 0; start_calib = 0;
            #50 rst_n = 1;
            #50 start_calib = 1; #10 start_calib = 0;
            wait(calib_done);
            #1000;
        end
        print_statistics();
        $finish;
    end
    
    // --- 统计打印任务 ---
    task print_statistics();
        $display("\n==========================================");
        $display("      MONTE CARLO STATISTICS SUMMARY      ");
        $display("==========================================");
        $display("Bit | Mean Ratio | Std Dev    | Min Ratio  | Max Ratio");
        $display("----|------------|------------|------------|-----------");
        
        for (int b = 6; b < CAP_NUM; b++) begin
            real sum, sum_sq;
            real min_r = 100.0, max_r = 0.0;
            real val, mean, std_dev;
            
            sum = 0; sum_sq = 0; // 显式清零

            for (int r = 0; r < MC_RUNS; r++) begin
                val = ratio_history[r][b];
                sum += val;
                sum_sq += val * val;
                if (val < min_r) min_r = val;
                if (val > max_r) max_r = val;
            end
            
            mean = sum / MC_RUNS;
            std_dev = $sqrt((sum_sq - MC_RUNS*mean*mean) / (MC_RUNS));
            
            $display("%3d | %10.6f | %10.6f | %10.6f | %10.6f", 
                     b, mean, std_dev, min_r, max_r);
        end
        $display("==========================================");
    endtask
    
    initial #50000000 begin $display("TIMEOUT"); $finish; end

endmodule