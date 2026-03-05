`timescale 1ns/1ps

// =============================================================================
// File Name     : tb_sar_recon.sv
// Module Name   : tb_sar_recon (Unit Testbench)
// Description   : sar_reconstruction 模块的独立验证环境。
//
// Verification Strategy:
//   1. Linearity Test: 扫描全量程输入，验证 INL/DNL 和分辨率缩放逻辑。
//   2. Update Test   : 动态修改权重，验证校准接口的灵敏度。
//   3. Throughput    : 满速流水线压力测试，验证握手逻辑和数据完整性。
//
// Update Note:
//   - [Fix] 调整 force_ideal_weights 生成逻辑，匹配 DUT 新的 TOTAL_SHIFT 参数。
//           模拟博士论文中的冗余权重幅值 (约 2^23)，防止输出饱和。
// =============================================================================

module tb_sar_recon;

    // --- 1. 参数配置 (必须与 RTL 保持一致) ---
    parameter int CAP_NUM       = 20;
    parameter int WEIGHT_WIDTH  = 30; // [Verified] 30-bit
    parameter int OUTPUT_WIDTH  = 16;
    parameter int FRAC_BITS     = 8;
    
    // --- 2. 信号声明 ---
    logic clk = 0, rst_n;
    logic recon_start;
    logic [CAP_NUM-1:0] raw_bits;
    logic signed [OUTPUT_WIDTH-1:0] adc_dout;
    logic data_valid_out;

    logic w_wr_en;
    logic [4:0] w_wr_addr;
    logic signed [WEIGHT_WIDTH-1:0] w_wr_data;
    
    // --- 3. 实例化 DUT (Device Under Test) ---
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
    
    // 100MHz 时钟生成
    initial forever #5 clk = ~clk; 

    // =========================================================================
    // [新增] 仿真专用：将 16-bit 重构结果导出为 TXT 文件供 MATLAB 分析
    // =========================================================================
    integer file_id;
    initial begin
        file_id = $fopen("adc_recon_sim_data.txt", "w");
        if (file_id == 0) begin
            $display("|  [ERROR]  | Cannot create adc_recon_sim_data.txt");
        end
    end

    // 全局捕获：只要有效信号拉高，就抓取当前的 ADC 结果写入文件
    always_ff @(posedge clk) begin
        if (data_valid_out) begin
            $fdisplay(file_id, "%d", $signed(adc_dout));
        end
    end
    // =========================================================================

    // --- 4. 辅助函数 ---
    
    // 函数：模拟理想 ADC 的采样过程
    // 输入: -1.0 ~ +1.0 的归一化电压
    // 输出: 20-bit 理想 SAR 码
    function logic [CAP_NUM-1:0] generate_ideal_bits(input real voltage);
        logic [63:0] full_scale_code;
        real scaled_v;
        real max_code;
        max_code = real'(longint'(1) << CAP_NUM) - 1.0;
        
        // 映射 [-1, 1] 到 [0, 2^N-1]
        // 注意：Split ADC 实际上是差分的，这里简化为单端码流生成用于测试
        scaled_v = (voltage + 1.0) / 2.0 * max_code;
        
        if (scaled_v < 0.0) scaled_v = 0.0;
        if (scaled_v > max_code) scaled_v = max_code;
        
        full_scale_code = longint'(scaled_v);
        return full_scale_code[CAP_NUM-1:0];
    endfunction

    function real abs(real val);
        if (val < 0) return -val;
        return val;
    endfunction

    // 任务：安全等待结果 (带 Watchdog 防止死锁)
    task wait_for_result(output bit success);
        integer timeout;
        success = 0;
        // [Update] 由于 DUT 为 2-3 级流水线，等待 10 个周期足矣
        for (timeout = 0; timeout < 20; timeout = timeout + 1) begin
            @(posedge clk);
            if (data_valid_out === 1'b1) begin
                success = 1;
                break; // 收到结果，退出等待
            end
        end
    endtask

    // 任务：初始化理想权重 (在下降沿驱动，防止 Setup Time 违例)
    // 目的：在校准算法运行前，先灌入"理想二进制权重"验证硬件通路。
    // 计算逻辑：W[i] = 2^(i + offset)。offset 用于匹配 DUT 内部的右移 FRAC_BITS。
    // 目标 MSB (W19) 约为 2^23，经过 DUT 的 >>1 和 >>8 处理后，输出约为 2^14 (半量程)。
    task force_ideal_weights();
        integer i;
        logic [63:0] calc_w;
        
        @(negedge clk); 
        for(i = 0; i < CAP_NUM; i = i + 1) begin
            w_wr_en   = 1;
            w_wr_addr = i;
            // 2^i * 2^4 = 2^(i+4). 当 i=19 时, W=2^23.
            calc_w = (longint'(1) << i) << 4; 
            w_wr_data = calc_w[WEIGHT_WIDTH-1:0];
            @(negedge clk);
        end
        w_wr_en = 0;
    endtask

    // --- 5. 测试用例集 ---

// Test 1: 线性度检查 (Linearity) - [已修复 Ideal 计算显示]
    task test_linearity();
        integer i;
        real vin;
        int ideal_expect; // 新增：用于存储计算出的理想值
        bit ok;
        
        $display("\n==================================================");
        $display(" TEST 1: Linearity Check (Expected Err < small LSB)");
        $display("==================================================");
        
        force_ideal_weights(); 

        $display("  Pt |    Vin (Norm)|      Raw Hex       |   Ideal |    Meas | Status");
        $display("-----|--------------|--------------------|---------|---------|--------");

        // 扫描 20 个电压点
        for (i = 0; i < 20; i = i + 1) begin 
            vin = -0.95 + (i * 1.9 / 19.0); // -0.95 到 +0.95
            
            // 生成输入给 DUT 的 Raw Bits
            raw_bits = generate_ideal_bits(vin);
            
            // [新增] 计算理论上的输出值 (16-bit 有符号数范围)
            // Vin 是归一化的 -1.0 ~ +1.0，乘以 32768 即可得到理论码值
            ideal_expect = int'(vin * 32768.0);

            @(negedge clk); recon_start = 1; 
            @(negedge clk); recon_start = 0;
            
            wait_for_result(ok);
            
            if (ok) begin
                // 修改了 $display，将 N/A 替换为 ideal_expect
                $display(" %3d | %9.4f    | %05h              | %7d | %7d | %s", 
                         i, vin, raw_bits, ideal_expect, $signed(adc_dout), 
                         (ideal_expect == $signed(adc_dout) || ideal_expect == $signed(adc_dout)-1 || ideal_expect == $signed(adc_dout)+1) ? "MATCH" : "DIFF");
            end else begin
                $display(" %3d | %9.4f    | %05h              | %7d | TIME_OUT| FAIL", 
                         i, vin, raw_bits, ideal_expect);
            end
        end
    endtask

    // Test 2: 权重更新验证
    task test_calibration_update();
        logic [63:0] base_w, err_w;
        bit ok;
        integer val_before, val_after;
        
        $display("\n==================================================");
        $display(" TEST 2: Weight Update (Sensitivity Check)");
        $display("==================================================");
        
        // 1. 设置输入为固定值 (MSB = 1, 其他 = 0)
        raw_bits = (longint'(1) << (CAP_NUM-1)); 

        // 2. 运行基线测试
        @(negedge clk); recon_start = 1; 
        @(negedge clk); recon_start = 0;
        wait_for_result(ok);
        val_before = $signed(adc_dout);
        $display(" [1] Baseline Output (with Ideal Weight): %d", val_before);
        
        // 3. 修改 MSB 权重：增加 10%
        $display(" [2] Injecting +10%% Error to MSB Weight...");
        @(negedge clk);
        base_w = (longint'(1) << (CAP_NUM - 1)) << 4; // 原理想值
        err_w  = (base_w * 11) / 10;                  // 增加 10%
        w_wr_en   = 1;
        w_wr_addr = CAP_NUM-1;
        w_wr_data = err_w[WEIGHT_WIDTH-1:0];
        @(negedge clk); w_wr_en = 0;
        
        // 4. 再次运行
        @(negedge clk); recon_start = 1; 
        @(negedge clk); recon_start = 0;
        wait_for_result(ok);
        val_after = $signed(adc_dout);
        $display(" [3] Output After Update                : %d", val_after);
        
        if (abs(val_after - val_before) > 100) 
            $display(" RESULT: PASS (Output shifted significantly as expected)");
        else
            $display(" RESULT: FAIL (Output did not change enough)");
    endtask

    // Test 3: 流水线吞吐量 (Throughput)
    task test_pipeline_throughput();
        integer i;
        integer rx_cnt;
        integer timeout;
        
        $display("\n==================================================");
        $display(" TEST 3: Pipeline Throughput (Input 5 packets continuous)");
        $display("==================================================");
        
        rx_cnt = 0;
        timeout = 0;

        fork
            // 线程 A: 发送端 (模拟高速 ADC 采样)
            begin
                for (i = 0; i < 5; i = i + 1) begin
                    @(negedge clk);
                    raw_bits = $random; // 随机数据
                    recon_start = 1;
                    $display(" [TX] Cycle %0t: Sent Input #%0d", $time, i+1);
                end
                @(negedge clk);
                recon_start = 0;
            end

            // 线程 B: 接收端 (检查是否有丢包)
            begin
                while (rx_cnt < 5 && timeout < 50) begin
                    @(posedge clk);
                    if (data_valid_out === 1'b1) begin
                        rx_cnt = rx_cnt + 1;
                        $display(" [RX] Cycle %0t: Received Output #%0d", $time, rx_cnt);
                    end
                    timeout = timeout + 1;
                end
            end
        join
        
        if (rx_cnt == 5) 
            $display(" RESULT: PASS (Received all 5 packets, Pipeline Full)");
        else              
            $display(" RESULT: FAIL (Lost packets, rx=%0d)", rx_cnt);
    endtask

    // --- 6. 主控流程 ---
    initial begin
        // 波形转储 (用于 Vivado/Verdi)
        $dumpfile("tb_sar_recon.vcd");
        $dumpvars(0, tb_sar_recon);

        // 系统复位
        rst_n = 0; w_wr_en = 0; recon_start = 0; raw_bits = 0;
        #50 rst_n = 1; 
        #20;

        // 执行测试序列
        test_linearity();
        test_calibration_update();
        test_pipeline_throughput();

        $display("\n==================================================");
        $display("                ALL TESTS COMPLETED               ");
        $display("==================================================");
        
        // [新增] 测试结束后关闭文件
        if (file_id != 0) $fclose(file_id); 
        
        $finish; 
    end

endmodule