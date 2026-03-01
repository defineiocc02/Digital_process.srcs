`timescale 1ns/1ps

/**
 * =============================================================================
 * File Name     : tb_gain_comp_check_lsb.sv
 * Description   : SAR ADC 校准算法验收验证平台 (工业标准版)
 * * Verification Logic:
 * 1. 模拟真实芯片制造 (包含 Bit0-5 的基准误差，会导致整体增益漂移)。
 * 2. 等待 RTL 校准完成，读取硬件算出的原始权重 (Raw Calibrated Weights)。
 * 3. 计算系统级增益补偿系数 K = Phy_MSB / Cal_MSB。
 * 4. 将所有校准值乘以 K (模拟后端数字补偿)。
 * 5. 计算最终的绝对残余误差 (Absolute Residue Error in LSB)。
 * 6. 判据：只要最大残余误差 < 0.5 LSB，即视为设计通过 (PASS)。
 * =============================================================================
 */

module tb_gain_comp_check_lsb;

    // --- 1. 参数配置 ---
    parameter int CAP_NUM       = 20;           // 电容总位数 (Bit 0 ~ 19)
    parameter int WEIGHT_WIDTH  = 30;           // 定点数位宽 (Q18.12)
    parameter int MC_RUNS       = 5;            // 蒙特卡洛仿真次数
    
    // --- 2. 信号声明 ---
    logic clk = 0;
    logic rst_n;
    logic start_calib, calib_done, calib_mode_en;
    logic comp_out;
    
    // 模拟前端接口
    logic [CAP_NUM-1:0] dac_p_force, dac_n_force;
    
    // 寄存器写回接口
    logic w_wr_en;
    logic [4:0] w_wr_addr;
    logic signed [WEIGHT_WIDTH-1:0] w_wr_data;

    // --- 3. 存储阵列 ---
    real phy_weights [CAP_NUM];      // "上帝视角"的物理真值 (Physical Truth)
    real stored_cal_vals [CAP_NUM];  // RTL 校准控制器算出的值 (Measured Value)
    
    // --- 4. DUT 实例化 (Device Under Test) ---
    // 请确保这里引用的模块名是您最新的串行计算版本
    sar_calib_ctrl_serial #(
        .CAP_NUM(CAP_NUM), 
        .WEIGHT_WIDTH(WEIGHT_WIDTH), 
        .AVG_LOOPS(32) 
    ) dut (.*);

    // 时钟生成: 100MHz
    initial forever #5 clk = ~clk;

    // --- 5. 模拟参数定义 ---
    real OFFSET_VOLTAGE = 5.0; // 5 LSB 固定失调 (用于验证斩波逻辑)
    real NOISE_RMS      = 0.5; // 0.5 LSB 随机噪声 (用于验证平均逻辑)
    real vp, vn, v_diff;

    // =========================================================================
    // 函数: 芯片制造 (模拟工艺偏差)
    // =========================================================================
    function automatic void manufacture_chip(int seed);
        real ideal_vals [CAP_NUM]; 
        real error;
        
        // 设置随机种子，确保每次 Run 的芯片体质不同
        $srandom(seed);
        
        // --- 理想权重表 (基于 Split-Cap 拓扑) ---
        ideal_vals[0]=1; ideal_vals[1]=2; ideal_vals[2]=4; ideal_vals[3]=8; ideal_vals[4]=16; ideal_vals[5]=32;
        ideal_vals[6]=33.53; ideal_vals[7]=67.05; ideal_vals[8]=134.10; ideal_vals[9]=268.20;
        ideal_vals[10]=316.91; ideal_vals[11]=316.91; ideal_vals[12]=633.81; ideal_vals[13]=1267.63; ideal_vals[14]=2535.25;
        ideal_vals[15]=5031.09; ideal_vals[16]=5031.09; ideal_vals[17]=10062.17; ideal_vals[18]=20124.35; ideal_vals[19]=40248.69;

        // --- 生成带有误差的物理权重 ---
        for(int i=0; i<CAP_NUM; i++) begin
            real base = ideal_vals[i] * 256.0; // 换算为 Q18.12 定点数 (1 LSB = 256)
            
            // [真实场景] Bit 0-5 也有误差，这会导致全局增益误差 (Gain Error)
            // 但只要线性度 (Linearity) 保持，增益误差可以通过乘法器消除。
            if(i <= 5) error = $dist_normal(seed, 0, 15) / 10000.0;  // 0.15% 偏差
            else       error = $dist_normal(seed, 0, 300) / 10000.0; // 3.00% 偏差
            
            phy_weights[i] = base * (1.0 + error);
        end
    endfunction

    // =========================================================================
    // 模拟模块: 比较器行为模型
    // =========================================================================
    always @(posedge clk) begin
        vp = 0; vn = 0;
        // 根据 DAC 驱动信号累加电荷
        for(int i=0; i<CAP_NUM; i++) begin
            if (dac_p_force[i]) vp += phy_weights[i];
            if (dac_n_force[i]) vn += phy_weights[i];
        end
        
        // Vdiff = (Vp - Vn) + Offset + Noise
        v_diff = vp - vn + OFFSET_VOLTAGE*256.0 + ($dist_normal($time,0,100)/100.0)*NOISE_RMS*256.0;
        
        // 比较器判决
        comp_out <= (v_diff > 0);
    end

    // =========================================================================
    // 辅助逻辑: 捕捉 RTL 输出的校准结果
    // =========================================================================
    always @(posedge clk) begin
        if (w_wr_en) begin
            stored_cal_vals[w_wr_addr] = real'(w_wr_data);
        end
    end

    // =========================================================================
    // 主测试流程 (验收核心)
    // =========================================================================
    initial begin
        // 变量声明 (必须放在 initial 块顶部以兼容所有仿真器)
        real gain_factor;
        real restored_val;
        real abs_err_lsb;
        real max_abs_err_lsb;
        real display_phy, display_restored;
        int run_idx, i;
        
        // --- [验收标准] ---
        // 允许的最大绝对误差 (INL)。对于 16-bit ADC，通常要求 < 0.5 LSB
        real ABS_ERR_LIMIT = 0.5; 

        $display("\n==========================================================================");
        $display("  SAR ADC CALIBRATION VERIFICATION (Criterion: Abs Error < %.1f LSB)", ABS_ERR_LIMIT);
        $display("==========================================================================");
        
        for (run_idx=0; run_idx<MC_RUNS; run_idx++) begin
            // 1. 制造一颗新芯片 (Seed 随 run_idx 变化)
            manufacture_chip(run_idx + 1000); 
            
            // 2. 启动校准
            rst_n = 0; start_calib = 0;
            #50 rst_n = 1; 
            #50 start_calib = 1; 
            #10 start_calib = 0;
            
            // 3. 等待完成 (额外延时确保最后一位写入 RAM)
            wait(calib_done);
            #200;
            
            // 4. 计算系统级增益补偿系数 K (基于 MSB)
            // K = 真实物理值 / 测量值
            // 这一步模拟了实际系统中通过参考电压测量增益的过程
            gain_factor = phy_weights[19] / stored_cal_vals[19];
            
            $display("\n--- Run %0d Analysis ---", run_idx);
            $display(">> System Gain Compensation Factor (K) : %.6f", gain_factor);
            $display("--------------------------------------------------------------------------");
            $display("Bit | Phy Val(LSB) | Restored(LSB) | Abs Error(LSB) | Status");
            $display("----|--------------|---------------|----------------|--------");

            max_abs_err_lsb = 0;
            
            // 5. 逐位检查 (从 Bit 6 开始，因为 0-5 是基准)
            for (i=6; i<CAP_NUM; i++) begin
                // [模拟后端补偿]: 测量值 * K
                restored_val = stored_cal_vals[i] * gain_factor;
                
                // [计算绝对误差]: (还原值 - 真值) / 256.0
                abs_err_lsb = (restored_val - phy_weights[i]) / 256.0;
                
                // 取绝对值
                if (abs_err_lsb < 0) abs_err_lsb = -abs_err_lsb;
                
                // 打印调试信息
                display_phy = phy_weights[i]/256.0;
                display_restored = restored_val/256.0;

                $display(" %2d | %12.2f | %13.2f | %12.4f   | %s", 
                         i+1, display_phy, display_restored, abs_err_lsb,
                         (abs_err_lsb < ABS_ERR_LIMIT) ? "PASS" : "BAD");
                         
                if (abs_err_lsb > max_abs_err_lsb) max_abs_err_lsb = abs_err_lsb;
            end
            
            $display("--------------------------------------------------------------------------");
            $display("Max Residual INL Error: %.4f LSB", max_abs_err_lsb);
            
            // 6. 最终判决
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