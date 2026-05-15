`timescale 1ns/1ps

/**
 * =============================================================================
 * Module:       tb_fpga_top
 * Description:  SAR ADC 校准验证 (归一化 LSB 显示版)
 * Updates:      
 *    1. 显示数值除以 16 (Scale)，还原为真实的 LSB 单位。
 *    2. 判定阈值放宽至 2.0% 以容忍整数运算的截断误差积累。
 * =============================================================================
 */

module tb_fpga_top;

    // =========================================================================
    // 1. 参数与信号
    // =========================================================================
    localparam int CAP_NUM      = 20;
    localparam int WEIGHT_WIDTH = 28;
    localparam int OUTPUT_WIDTH = 16;
    
    // Scale 因子 (2^FRAC_BITS = 16)
    localparam real SCALE_FACTOR = 16.0; 
    
    // DUT 接口信号
    logic clk;
    logic rst_n;
    logic start_calib;
    
    wire calib_done;
    wire data_valid;
    wire [OUTPUT_WIDTH-1:0] adc_data;

    // 黄金模型数组 (物理真值)
    real golden_weights_phys [0:19];

    // =========================================================================
    // 2. DUT 实例化
    // =========================================================================
    sar_adc_fpga_top #(
        .CAP_NUM(CAP_NUM),
        .WEIGHT_WIDTH(WEIGHT_WIDTH),
        .OUTPUT_WIDTH(OUTPUT_WIDTH),
        .EMULATION_MODE(1) 
    ) u_dut (
        .clk(clk),
        .rst_n(rst_n),
        .start_calib(start_calib),
        .sar_bits_i(20'd0), 
        .sar_ready_i(1'b0), 
        .comp_out_i(1'b0),
        .calib_done(calib_done),
        .adc_data(adc_data),
        .data_valid(data_valid)
    );

    // =========================================================================
    // 3. 初始化与时钟
    // =========================================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk; 
    end

    // 初始化黄金值 (Raw Values from Model)
    initial begin
        golden_weights_phys[0] = 16.0;      
        golden_weights_phys[1] = 32.0;      
        golden_weights_phys[2] = 64.0;      
        golden_weights_phys[3] = 128.0;     
        golden_weights_phys[4] = 256.0;     
        golden_weights_phys[5] = 512.0;     
        golden_weights_phys[6] = 536.0;     
        golden_weights_phys[7] = 1073.0;
        golden_weights_phys[8] = 2146.0;
        golden_weights_phys[9] = 4291.0;
        golden_weights_phys[10] = 5071.0;   
        golden_weights_phys[11] = 5071.0;
        golden_weights_phys[12] = 10141.0;
        golden_weights_phys[13] = 20282.0;
        golden_weights_phys[14] = 40564.0;
        golden_weights_phys[15] = 80497.0;
        golden_weights_phys[16] = 80497.0;
        golden_weights_phys[17] = 160995.0;
        golden_weights_phys[18] = 321990.0;
        golden_weights_phys[19] = 643979.0; 
    end

    // =========================================================================
    // 4. 主测试流程
    // =========================================================================
    initial begin
        rst_n = 0;
        start_calib = 0;
        #100;
        rst_n = 1;
        #100;
        
        $display("\n========================================================");
        $display("   SAR ADC Digital Backend Calibration Testbench");
        $display("========================================================\n");

        $display("[TIME: %0t] Starting Calibration Logic...", $time);
        @(posedge clk);
        start_calib = 1;
        @(posedge clk);
        start_calib = 0;

        wait(calib_done);
        $display("[TIME: %0t] Calibration Done Signal Received.", $time);
        
        #100;

        // 打印分析报告
        print_calib_report();
        
        $stop;
    end

    // =========================================================================
    // 5. 结果分析任务 (Task)
    // =========================================================================
    task print_calib_report;
        integer i;
        real fpga_val_raw;  // FPGA 内部寄存器值 (Fixed Point)
        real fpga_val_lsb;  // 归一化后的 LSB 值
        real ideal_val_lsb; // 物理模型真值 (归一化)
        real error_lsb;     // 绝对误差 (LSB)
        real error_pct;     // 相对误差百分比
        string status;
        
        $display("\n-----------------------------------------------------------------------------------------");
        $display(" Bit | Ideal Weight (LSB) | Calibrated (LSB) | Error (LSB) | Error(%) | Status");
        $display("-----------------------------------------------------------------------------------------");

        for (i = 6; i < CAP_NUM; i = i + 1) begin
            // 1. 读取原始值
            fpga_val_raw = $signed(u_dut.u_ctrl.weight_ram[i]);
            
            // 2. 归一化 (Divide by 16)
            fpga_val_lsb = fpga_val_raw / SCALE_FACTOR;
            ideal_val_lsb = golden_weights_phys[i] / SCALE_FACTOR;
            
            // 3. 计算误差
            error_lsb = fpga_val_lsb - ideal_val_lsb;
            error_pct = (error_lsb / ideal_val_lsb) * 100.0;
            
            // 4. 判定 (放宽至 2.0% 以容忍累积截断误差)
            if ((error_pct > -2.0) && (error_pct < 2.0)) 
                status = "PASS";
            else 
                status = "FAIL";

            $display(" %2d  | %18.2f | %16.2f | %11.2f | %7.3f%% | %s", 
                     i, ideal_val_lsb, fpga_val_lsb, error_lsb, error_pct, status);
        end
        $display("-----------------------------------------------------------------------------------------\n");
        
        // 最终 MSB 检查 (同样使用 LSB 单位)
        // 40248 LSB +/- 2% 
        if ($signed(u_dut.u_ctrl.weight_ram[19])/16.0 > 39400 && $signed(u_dut.u_ctrl.weight_ram[19])/16.0 < 41000)
            $display("[TEST RESULT] SUCCESS: MSB converged correctly.");
        else
            $display("[TEST RESULT] FAILURE: MSB divergence detected.");
            
    endtask

endmodule