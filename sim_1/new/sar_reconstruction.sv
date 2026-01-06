`timescale 1ns/1ps

// =============================================================================
// File Name     : sar_reconstruction.sv
// Module Name   : sar_reconstruction
// Description   : SAR ADC 数字重构引擎 (Digital Reconstruction Engine)
//                 基于裂式采样 (Split-Sampling) 架构，将非理想的 SAR 原始码流
//                 通过线性加权求和，还原为高精度的 16-bit 线性电压值。
//
// Functionality : V_out = (Σ (D_i * W_i)) * Scale_Factor + Offset_Comp
//
// Key Features  :
//   1. [Robustness] 40-bit 宽动态范围累加器，防止中间级溢出。
//   2. [Precision] 纯有符号数 (Signed) 运算管线，确保补码逻辑正确。
//   3. [Accuracy] 内置 +0.5 LSB 偏置补偿，消除量化截断误差 (DC Offset)。
//   4. [Flexibility] 动态权重更新接口，支持前台校准算法实时写入。
//
// Parameters    :
//   CAP_NUM       : 电容阵列总位数 (默认 20)。
//   WEIGHT_WIDTH : 权重存储位宽 (默认 30，适配 2^27 量级的定点数)。
//   OUTPUT_WIDTH : 最终输出位宽 (默认 16-bit)。
//   FRAC_BITS    : 权重的小数部分位宽 (默认 8-bit, Q22.8 格式)。
//
// Ports         :
//   clk            : 全局时钟
//   rst_n          : 全局异步复位 (低有效)
//   data_valid_in  : SAR 转换完成标志
//   raw_bits       : 原始 SAR 码流 (D_out)
//   w_wr_en        : 权重写使能 (来自校准控制器)
//   w_wr_addr      : 权重写地址 (0~19)
//   w_wr_data      : 校准后的新权重 (30-bit 有符号数)
//   adc_dout       : 线性化后的 ADC 输出 (16-bit 有符号数)
//   data_valid_out : 输出有效标志
//
// Design Notes  :
//   1. 权重存储采用本地 RAM 阵列，上电后必须由校准控制器初始化。
//   2. 采用两级流水线设计：第一级差分累加，第二级缩放与饱和。
//      [Update] 为改善时序，第一级累加已被拆分为 Pipeline Stage 1 (Partial) 和 Stage 2 (Global)。
//   3. +0.5 LSB 补偿确保四舍五入，消除 Floor 截断带来的 -0.5 LSB 系统偏差。
//   4. 所有中间计算使用显式有符号数，防止 Verilog 无符号提升陷阱。
// =============================================================================

module sar_reconstruction #(
    parameter int CAP_NUM       = 20, 
    parameter int WEIGHT_WIDTH  = 30, // [Design Note] 必须 >= 28 以容纳 MSB 权重
    parameter int OUTPUT_WIDTH  = 16, 
    parameter int FRAC_BITS     = 8
)(
    // --- Global Signals ---
    input  logic                          clk,
    input  logic                          rst_n,
    
    // --- Data Path Input (From SAR Logic) ---
    input  logic                          data_valid_in, // SAR 转换完成标志
    input  logic [CAP_NUM-1:0]            raw_bits,      // 原始 SAR 码流 (D_out)
    
    // --- Calibration Interface (From Calib Ctrl) ---
    input  logic                          w_wr_en,       // 写使能
    input  logic [4:0]                    w_wr_addr,     // 权重地址 (0~19)
    input  logic signed [WEIGHT_WIDTH-1:0] w_wr_data,    // 校准后的新权重
    
    // --- Data Path Output (To User/Bus) ---
    output logic signed [OUTPUT_WIDTH-1:0] adc_dout,      // 线性化后的 ADC 输出
    output logic                          data_valid_out // 输出有效标志
);

    // =========================================================================
    // 1. 本地权重存储阵列 (Local Weight Memory)
    // =========================================================================
    // 存储每个 bit 对应的物理权重。
    // 初始化值仅用于防止不定态，实际工作时必须由 sar_calib_ctrl 模块写入校准值。
    logic signed [WEIGHT_WIDTH-1:0] weight_ram [0:CAP_NUM-1];

    initial begin
        for (int k=0; k<CAP_NUM; k++) weight_ram[k] = 30'd0;
    end

    // 同步写端口
    always_ff @(posedge clk) begin
        if (w_wr_en) weight_ram[w_wr_addr] <= w_wr_data;
    end

    // =========================================================================
    // 2. 流水线优化：第一级累加拆分为 Partial Accumulation (Stage 1)
    // =========================================================================
    // 原逻辑在一个周期内完成 20 个 40-bit 加减法，是关键路径瓶颈。
    // 现优化为两级流水线：
    // Stage 1: 将 20 个输入分为 4 组，并行计算 4 个部分和。
    // =========================================================================
    logic signed [39:0] partial_sums [0:3]; 
    logic               vld_pipe_s1;
    
    // 20 inputs / 4 groups = 5 inputs per group
    localparam int GROUP_SIZE = 5; 

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for(int k=0; k<4; k++) partial_sums[k] <= 0;
            vld_pipe_s1 <= 0;
        end else begin
            if (data_valid_in) begin
                for (int g=0; g<4; g++) begin
                    automatic logic signed [39:0] acc_group = 0;
                    for (int i=0; i<GROUP_SIZE; i++) begin
                        int idx = g * GROUP_SIZE + i;
                        if (idx < CAP_NUM) begin
                            // [CRITICAL DESIGN] 强制类型转换
                            if (raw_bits[idx]) 
                                acc_group = acc_group + signed'(40'(weight_ram[idx]));
                            else             
                                acc_group = acc_group - signed'(40'(weight_ram[idx]));
                        end
                    end
                    partial_sums[g] <= acc_group;
                end
                vld_pipe_s1 <= 1;
            end else begin
                vld_pipe_s1 <= 0;
            end
        end
    end

    // =========================================================================
    // 3. 流水线优化：第二级累加 (Global Accumulation - Stage 2)
    // =========================================================================
    // 将部分和相加得到最终结果 sum_stage2
    // =========================================================================
    logic signed [39:0] sum_stage2;
    logic               vld_pipe_s2;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sum_stage2 <= 0;
            vld_pipe_s2 <= 0;
        end else begin
            if (vld_pipe_s1) begin
                sum_stage2 <= partial_sums[0] + partial_sums[1] + 
                              partial_sums[2] + partial_sums[3];
                vld_pipe_s2 <= 1;
            end else begin
                vld_pipe_s2 <= 0;
            end
        end
    end

    // =========================================================================
    // 4. 流水线第三级：缩放、偏置补偿与饱和 (Scaling & Saturation)
    // =========================================================================
    // 目标: 将 40-bit 高精度定点数映射回 16-bit 输出范围 [-32768, +32767]。
    //
    // 操作步骤:
    //   a. 除以 2 (ASR): 因为差分累加的动态范围是 2*Vref，需归一化。
    //   b. 加 0.5 LSB: 消除 Floor 截断带来的 -0.5 LSB 系统性偏差 (DC Offset)。
    //   c. 算术右移: 去除小数位并对齐到目标分辨率。
    //   d. 饱和钳位: 防止数值溢出导致极性翻转。
    // =========================================================================
    
    // [Fix] 移位量修正
    // 权重 W19 ~ 2^23 (Q22.8), 输出 MSB ~ 2^15. 
    // 2^23 -> 2^15 需要右移 8 位。
    // 原公式 (20-16)+8 = 12 会导致输出幅度过小。
    // 正确的移位量应当仅为 FRAC_BITS (假设权重已归一化到输出量程)
    localparam int TOTAL_SHIFT = FRAC_BITS; 

    // 中间变量 (显式声明以便于 Debug 和波形观察)
    logic signed [39:0] val_step1_div2;
    logic signed [39:0] val_step2_round;
    logic signed [39:0] val_step3_shift;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            adc_dout <= 0;
            data_valid_out <= 0;
        end else begin
            if (vld_pipe_s2) begin
                // Step 1: 差分除以 2 (算术右移，保留符号位)
                val_step1_div2 = sum_stage2 >>> 1;
                
                // Step 2: 加 0.5 LSB 进行舍入 (Round to Nearest)
                // [CRITICAL DESIGN] 必须使用 '40'sd1' 声明为有符号数。
                // 若写成 '1'，编译器会将其视为无符号数，导致负数参与运算时被提升为巨大的正数！
                val_step2_round = val_step1_div2 + (40'sd1 <<< (TOTAL_SHIFT - 1));
                
                // Step 3: 最终移位 (降采样)
                val_step3_shift = val_step2_round >>> TOTAL_SHIFT;
                
                // Step 4: 饱和输出 (Saturation Logic)
                // 检查是否超出了 16-bit 有符号数范围
                if (val_step3_shift > 32767)       
                    adc_dout <= 32767;
                else if (val_step3_shift < -32768) 
                    adc_dout <= -32768;
                else                       
                    adc_dout <= val_step3_shift[15:0]; // 安全截断
                
                data_valid_out <= 1;
            end else begin
                data_valid_out <= 0;
            end
        end
    end

endmodule