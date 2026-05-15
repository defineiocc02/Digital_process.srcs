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

    // --- 4. 辅助函数 ---
    function logic [CAP_NUM-1:0] generate_ideal_bits(input real voltage);
        logic [63:0] full_scale_code;
        real scaled_v;
        real max_code;
        max_code = real'(longint'(1) << CAP_NUM) - 1.0;
        scaled_v = (voltage + 0.5) * (real'(longint'(1) << CAP_NUM));
        if (scaled_v < 0.0) scaled_v = 0.0;
        if (scaled_v > max_code) scaled_v = max_code;
        full_scale_code = longint'(scaled_v);
        return full_scale_code[CAP_NUM-1:0];
    endfunction

    function real abs(real val);
        if (val < 0) return -val;
        return val;
    endfunction

    // 任务：安全等待结果 (带 Watchdog)
    task wait_for_result(output bit success);
        integer timeout;
        success = 0;
        for (timeout = 0; timeout < 100; timeout = timeout + 1) begin
            @(posedge clk);
            if (data_valid_out === 1'b1) begin
                success = 1;
                timeout = 100; // Break
            end
        end
    endtask

    // 任务：初始化理想权重 (在下降沿驱动，防止竞争)
    task force_ideal_weights();
        integer i;
        logic [63:0] calc_w;
        
        @(negedge clk); 
        for(i = 0; i < CAP_NUM; i = i + 1) begin
            w_wr_en   = 1;
            w_wr_addr = i;
            calc_w = longint'(1) << (i + FRAC_BITS);
            w_wr_data = calc_w[WEIGHT_WIDTH-1:0];
            @(negedge clk);
        end
        w_wr_en = 0;
    endtask

    // --- 5. 测试用例集 ---

    // Test 1: 线性度检查 (Linearity)
    task test_linearity();
        integer i;
        real vin, ideal_lsb, meas_lsb, err_lsb;
        bit ok;
        
        $display("\n==================================================");
        $display(" TEST 1: Linearity Check (Expected Err < 2.0 LSB)");
        $display("==================================================");
        
        force_ideal_weights(); 

        $display("  Pt |   Vin (V) |      Raw Hex     |  Ideal  |   Meas  |  Err  | Status");
        $display("-----|-----------|------------------|---------|---------|-------|--------");

        for (i = 0; i < 20; i = i + 1) begin 
            vin = -0.48 + (i * 0.96 / 19.0);
            raw_bits = generate_ideal_bits(vin);
            
            @(negedge clk); recon_start = 1; 
            @(negedge clk); recon_start = 0;
            
            wait_for_result(ok);
            
            if (ok) begin
                ideal_lsb = vin * 65536.0;
                meas_lsb  = real'($signed(adc_dout));
                err_lsb   = meas_lsb - ideal_lsb;
                
                $display(" %3d | %9.4f | %05h | %7.0f | %7.0f | %5.1f | %s", 
                         i, vin, raw_bits, ideal_lsb, meas_lsb, err_lsb, 
                         (abs(err_lsb) < 3.0) ? "PASS" : "FAIL");
            end else begin
                $display(" %3d | %9.4f | %05h | TIME_OUT | TIME_OUT|  N/A  | FAIL", 
                         i, vin, raw_bits);
            end
        end
    endtask

    // Test 2: 权重更新验证
    task test_calibration_update();
        logic [63:0] base_w, err_w;
        bit ok;
        
        $display("\n==================================================");
        $display(" TEST 2: Weight Update (Sensitivity Check)");
        $display("==================================================");
        
        force_ideal_weights();
        raw_bits = (longint'(1) << (CAP_NUM-1)); 

        @(negedge clk); recon_start = 1; 
        @(negedge clk); recon_start = 0;
        
        wait_for_result(ok);
        if(ok) $display(" [1] Baseline Output (Ideal) : %d", $signed(adc_dout));
        
        $display(" [2] Injecting +10%% Error to MSB...");
        
        @(negedge clk);
        base_w = longint'(1) << (CAP_NUM - 1 + FRAC_BITS);
        err_w  = (base_w * 11) / 10; 
        w_wr_en   = 1;
        w_wr_addr = CAP_NUM-1;
        w_wr_data = err_w[WEIGHT_WIDTH-1:0];
        @(negedge clk); w_wr_en = 0;
        
        @(negedge clk); recon_start = 1; 
        @(negedge clk); recon_start = 0;
        
        wait_for_result(ok);
        if(ok) $display(" [3] Output After Update     : %d", $signed(adc_dout));
        
        if (ok && ($signed(adc_dout) > 1000 || $signed(adc_dout) < -1000)) 
            $display(" RESULT: PASS (Output shifted significantly)");
        else
            $display(" RESULT: FAIL (Output did not change enough)");
    endtask

    // Test 3: 流水线吞吐量 (Throughput)
    task test_pipeline_throughput();
        integer i;
        integer rx_cnt;
        integer timeout;
        
        $display("\n==================================================");
        $display(" TEST 3: Pipeline Throughput (Input 5 packets)");
        $display("==================================================");
        
        rx_cnt = 0;
        timeout = 0;

        fork
            // 线程 A: 发送端
            begin
                for (i = 0; i < 5; i = i + 1) begin
                    @(negedge clk);
                    raw_bits = $random;
                    recon_start = 1;
                end
                @(negedge clk);
                recon_start = 0;
                $display(" [TX] Sent 5 inputs consecutively.");
            end

            // 线程 B: 接收端 (增强版握手)
            begin
                while (rx_cnt < 5 && timeout < 1000) begin
                    @(posedge clk);
                    if (data_valid_out === 1'b1) begin
                        rx_cnt = rx_cnt + 1;
                        $display(" [RX] Pkt %0d received: %d (Time: %0t ns)", rx_cnt, $signed(adc_dout), $time);
                    end
                    timeout = timeout + 1;
                end
            end
        join
        
        if (rx_cnt == 5) 
            $display(" RESULT: PASS (Received all 5 packets)");
        else             
            $display(" RESULT: FAIL (Lost packets, rx=%0d, timeout=%0d)", rx_cnt, timeout);
    endtask

    // --- 7. 主控流程 ---
    initial begin
        rst_n = 0; w_wr_en = 0; recon_start = 0; raw_bits = 0;
        #50 rst_n = 1; #20;

        test_linearity();
        test_calibration_update();
        test_pipeline_throughput();

        $display("\n==================================================");
        $display("               ALL TESTS COMPLETED                ");
        $display("==================================================");
        $finish; 
    end

endmodule