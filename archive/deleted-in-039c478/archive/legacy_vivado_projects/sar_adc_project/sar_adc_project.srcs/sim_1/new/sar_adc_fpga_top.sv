/* =============================================================================
 * Module:       lfsr_16b
 * Description:  伪随机噪声发生器 (Dither Source)
 * Role:         模拟 ASIC 比较器的热噪声，使 SRM 线性化有效。
 * =============================================================================
 */
module lfsr_16b (
    input  wire clk,
    input  wire rst_n,
    input  wire enable,
    output wire [15:0] noise_out
);
    logic [15:0] lfsr_reg;
    
    // 多项式 X^16 + X^14 + X^13 + X^11 + 1
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lfsr_reg <= 16'hACE1; // 非零种子
        end else if (enable) begin
            lfsr_reg <= {lfsr_reg[14:0], lfsr_reg[15] ^ lfsr_reg[13] ^ lfsr_reg[12] ^ lfsr_reg[10]};
        end
    end
    
    // 将 16-bit 随机数缩放到 +/- 1.0 LSB 范围 (模拟噪声)
    // 假设 ADC 模型接受定点数，这里直接输出 raw code，在 model 里缩放
    assign noise_out = lfsr_reg;
endmodule