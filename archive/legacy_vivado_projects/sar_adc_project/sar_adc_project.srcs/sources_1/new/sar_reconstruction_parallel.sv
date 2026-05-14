`timescale 1ns/1ps
/**
 * =================================================================================================
 * Module:       sar_reconstruction_parallel
 *
 * Description:
 *   并行加法树 (Adder Tree) 形式的 SAR ADC 数字重构模块。
 *   本模块将 SAR 比较结果 (raw_bits) 与校准后的电容权重 (weight_ram)，
 *   以及 SRM 校准残差 (srm_residue) 融合，生成最终 ADC 数字输出码。
 *
 * Architecture & Performance:
 *   - Throughput : 1 sample / clock (fully pipelined)
 *   - Latency    : 1 clock cycle
 *   - Structure  : 全组合并行加法树 + 单级输出寄存
 *
 * Target Use Case:
 *   - 高速 SAR ADC (≥50 MS/s)
 *   - 数字时钟与采样时钟同频系统
 *   - 对低延迟与时序收敛要求严格的应用
 *
 * Mathematical Model (Differential DAC):
 *
 *   D_out = Q { 1/2 * Σ[(2·b_i - 1)·W_i] + ΔW_SRM }
 *
 *   where:
 *     b_i        : SAR raw decision bit
 *     W_i        : calibrated capacitor weight
 *     ΔW_SRM     : residue correction from SRM calibration
 *     Q(·)       : rounding + truncation + saturation
 *
 * Assumptions:
 *   - 权重 W_i 为正值，且单调递减
 *   - srm_residue 已与权重处于同一量纲 (post-normalization)
 *   - FRAC_BITS 定义了内部定点小数位数
 * =================================================================================================
 */
module sar_reconstruction_parallel #(
    parameter int CAP_NUM      = 20,  // 电容阵列位数
    parameter int WEIGHT_WIDTH = 28,  // 权重位宽 (定点表示)
    parameter int OUTPUT_WIDTH = 16,  // ADC 输出位宽
    parameter int DAC_ARCH     = 1,   // 1: 差分 DAC, 0: 单端 DAC
    parameter int FRAC_BITS    = 4    // 内部定点小数位数
)(
    input  wire        clk,
    input  wire        rst_n,

    // ---------------- 数据流接口 ----------------
    input  wire                    data_valid_in, // 输入数据有效
    input  wire [CAP_NUM-1:0]      raw_bits,       // SAR 原始比较结果

    // ---------------- 权重更新接口 ----------------
    input  wire                    w_wr_en,        // 权重写使能
    input  wire [4:0]              w_wr_addr,      // 权重地址
    input  wire [WEIGHT_WIDTH-1:0] w_wr_data,      // 权重数据

    // ---------------- SRM 校准残差 ----------------
    // 注意：srm_residue 必须与 ΣW_i / 2 处于同一数值量纲
    input  wire signed [WEIGHT_WIDTH-1:0] srm_residue,

    // ---------------- 输出接口 ----------------
    output logic                   data_valid_out, // 输出数据有效
    output logic signed [OUTPUT_WIDTH-1:0] adc_dout // ADC 数字输出
);

    // =============================================================================================
    // 1. 权重存储 (Weight RAM)
    //    存储校准后的电容权重 W_i
    // =============================================================================================
    logic [WEIGHT_WIDTH-1:0] weight_ram [0:CAP_NUM-1];

    // =============================================================================================
    // 2. 饱和阈值定义
    //    用于防止数值溢出，确保输出落在 ADC 合法码域
    // =============================================================================================
    localparam signed [31:0] MAX_POS = 32'sd32767;
    localparam signed [31:0] MAX_NEG = -32'sd32768;

    // =============================================================================================
    // 3. 权重写入逻辑
    //    通常由后台校准 FSM 或启动校准模块驱动
    // =============================================================================================
    always_ff @(posedge clk) begin
        if (w_wr_en)
            weight_ram[w_wr_addr] <= w_wr_data;
    end

    // =============================================================================================
    // 4. 并行加法树 (Combinational Adder Tree)
    //
    //    数学等价:
    //      sum_total = Σ[(2·b_i - 1)·W_i]    (差分 DAC)
    //
    //    说明:
    //      - 使用 always_comb + for 循环描述
    //      - 综合器会自动映射为平衡加法器树
    // =============================================================================================
    logic signed [31:0] sum_total;

    always_comb begin
        sum_total = 0;

        for (int i = 0; i < CAP_NUM; i++) begin
            if (DAC_ARCH == 1) begin
                // ---------------- 差分 DAC ----------------
                // raw_bits[i] = 1 → +W_i
                // raw_bits[i] = 0 → -W_i
                if (raw_bits[i])
                    sum_total = sum_total + $signed(weight_ram[i]);
                else
                    sum_total = sum_total - $signed(weight_ram[i]);
            end else begin
                // ---------------- 单端 DAC ----------------
                // raw_bits[i] = 1 → +W_i
                // raw_bits[i] = 0 → +0
                if (raw_bits[i])
                    sum_total = sum_total + $signed(weight_ram[i]);
            end
        end
    end

    // =============================================================================================
    // 5. 输出流水线寄存 (1-cycle latency)
    //
    //    Pipeline Stages:
    //      (1) 差分归一化:     sum_total / 2
    //      (2) SRM 残差融合:   + srm_residue
    //      (3) 定点舍入:       round-to-nearest (half-up)
    //      (4) 饱和截断:       限制至 ADC 输出范围
    // =============================================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_valid_out <= 1'b0;
            adc_dout       <= '0;
        end else begin
            // 有效标志延迟一拍，与输出数据对齐
            data_valid_out <= data_valid_in;

            // 仅在输入有效时更新数据，降低无效切换功耗
            if (data_valid_in) begin
                automatic logic signed [31:0] final_val;

                // (1) 差分归一化 + SRM 校准残差
                //     等价于: 1/2·Σ[(2·b_i - 1)·W_i] + ΔW_SRM
                final_val = (sum_total >>> 1) + srm_residue;

                // (2) 定点舍入
                //     round-half-up 实现
                final_val = (final_val + (1 << (FRAC_BITS-1))) >>> FRAC_BITS;

                // (3) 饱和截断
                if (final_val > MAX_POS)
                    adc_dout <= MAX_POS;
                else if (final_val < MAX_NEG)
                    adc_dout <= MAX_NEG;
                else
                    adc_dout <= final_val[OUTPUT_WIDTH-1:0];
            end
        end
    end

endmodule
