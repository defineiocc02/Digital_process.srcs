`timescale 1ns/1ps

// =============================================================================
// Module Name   : sar_adc_controller
// Description   : 纯硬件实现的 SAR 逻辑控制器 (Successive Approximation Register)
//                 替代 Testbench 中的软件 Task，实现真实的逐次逼近时序。
// =============================================================================
module sar_adc_controller #(
    parameter int CAP_NUM = 20  // ADC 分辨率 (Bit 0 ~ 19)
)(
    input  wire                 clk,
    input  wire                 rst_n,
    
    // --- 控制接口 (Handshake) ---
    input  wire                 start,        // 启动脉冲
    output reg                  eoc,          // End of Conversion (转换完成)
    output reg [CAP_NUM-1:0]    result_out,   // 最终并行数据
    output reg                  result_valid, // 结果有效标志
    
    // --- 模拟前端接口 (PHY Interface) ---
    input  wire                 comp_out,     // 比较器输入 (1: DAC > Vin, 0: DAC < Vin)
    output reg  [CAP_NUM-1:0]   dac_p_force   // 输出给电容阵列的控制码
);

    // --- 状态机定义 ---
    typedef enum logic [1:0] {
        S_IDLE,    // 空闲态
        S_SAMPLE,  // 采样态 (预留，本例中快速跳过)
        S_CONVERT, // 转换态 (核心 SAR 循环)
        S_DONE     // 完成态
    } state_t;

    state_t state;

    // --- 内部寄存器 ---
    logic [$clog2(CAP_NUM)-1:0] bit_ptr;  // 指针：当前操作位
    logic [CAP_NUM-1:0]         sar_reg;  // 寄存器：存储逼近过程中的码字
    logic                       phase;    // 相位控制：0=Set DAC, 1=Latch Comp

    // =========================================================================
    // FSM & Datapath
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_IDLE;
            bit_ptr      <= CAP_NUM - 1;
            sar_reg      <= '0;
            phase        <= 0;
            eoc          <= 0;
            result_valid <= 0;
            result_out   <= '0;
        end else begin
            // 默认脉冲复位
            eoc          <= 0;
            result_valid <= 0;

            case (state)
                S_IDLE: begin
                    sar_reg <= '0;
                    phase   <= 0;
                    if (start) state <= S_SAMPLE;
                end

                S_SAMPLE: begin
                    // 实际设计中这里控制采样开关 (Bootstrapped Switch)
                    // 本例直接进入转换，并预置 MSB (Bit 19)
                    state   <= S_CONVERT;
                    bit_ptr <= CAP_NUM - 1; 
                    
                    // [动作]: 预置 MSB 为 1 (Trial)
                    sar_reg              <= '0;
                    sar_reg[CAP_NUM - 1] <= 1'b1; 
                    phase   <= 0;
                end

                S_CONVERT: begin
                    if (phase == 0) begin
                        // --- Phase 0: DAC Settling ---
                        // 等待 DAC 输出电压稳定，比较器前置放大器建立
                        phase <= 1;
                    end else begin
                        // --- Phase 1: Comparator Latch & Shift ---
                        
                        // 1. 根据比较器结果决定当前位 (Check)
                        // 如果 comp_out=1 (DAC > Vin)，说明刚置的 1 太大了，必须撤销(置0)
                        if (comp_out) begin
                            sar_reg[bit_ptr] <= 1'b0; 
                        end
                        // 否则保持 1 (Keep)

                        // 2. 移位逻辑 (Shift)
                        if (bit_ptr == 0) begin
                            state <= S_DONE;
                        end else begin
                            bit_ptr <= bit_ptr - 1;
                            // [动作]: 下一位预置为 1 (Next Trial)
                            // 注意：这里是对寄存器的下一位进行操作，保留当前位的决定
                            sar_reg[bit_ptr - 1] <= 1'b1;
                            phase <= 0; // 回到 Phase 0 等待新电压建立
                        end
                    end
                end

                S_DONE: begin
                    result_out   <= sar_reg;
                    result_valid <= 1;
                    eoc          <= 1;
                    state        <= S_IDLE;
                end
            endcase
        end
    end

    // --- 输出逻辑 ---
    // 将内部寄存器实时送给 PHY
    always_comb begin
        dac_p_force = sar_reg;
    end

endmodule