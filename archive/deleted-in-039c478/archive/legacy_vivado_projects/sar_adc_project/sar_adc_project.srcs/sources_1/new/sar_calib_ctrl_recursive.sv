`timescale 1ns/1ps

// =============================================================================
// File Name     : sar_calib_ctrl_recu_ref.sv
// Module Name   : sar_calib_ctrl_recu_ref
// Description   : 高精度 Split-Sampling SAR ADC 前台递归校准控制器
//
// Functionality :
//   实现基于 "Measure-then-Set" 策略的递归校准算法。利用低位已校准电容（存储
//   在 Shadow RAM 中）作为参考 DAC，通过二分搜索测量高位电容的实际权重。
//   包含失调消除和 MSB 过压保护机制。
//
// Key Features  :
//   1. 递归测量 (Recursive Measurement): 利用低位组合测量高位
//   2. 失调消除 (Offset Cancellation): 采用 (P+N)/2 差分测量法
//   3. MSB 保护 (MSB Protection): 强制反接次高位以压缩共模范围，并在数字域补偿
//   4. 影子存储 (Shadow RAM): 实时维护已校准权重表
//
// Parameters    :
//   CAP_NUM       : 总电容位数 (默认 20)
//   WEIGHT_WIDTH  : 权重定点数位宽 (默认 30, Q18.12)
//   COMP_WAIT_CYC : 比较器/DAC 建立时间周期数 (默认 16)
//   AVG_LOOPS     : 平均次数 (默认 32, 需为 2 的幂)
//   MAX_CALIB_BIT : 免校准 LSB 段最高位 (默认 5)
//
// Ports         :
//   clk           : 系统时钟
//   rst_n         : 异步复位 (低有效)
//   start_calib   : 校准启动脉冲
//   calib_done    : 校准完成标志
//   calib_mode_en : 校准模式使能指示
//   comp_out      : 比较器输出 (1: Vp > Vn)
//   dac_p_force   : P 端 DAC 强制控制信号
//   dac_n_force   : N 端 DAC 强制控制信号
//   w_wr_en       : 权重写回使能
//   w_wr_addr     : 权重写回地址
//   w_wr_data     : 权重写回数据
//
// Design Notes  :
//   1. [CRITICAL] 针对 Bit 18/19 的校准启用了特殊保护逻辑，需配合模拟阵列连接
//   2. Shadow RAM 初始化必须保证低位 (Bit 0-5) 为理想二进制权重
// =============================================================================

module sar_calib_ctrl_recu_ref #(
    parameter int CAP_NUM       = 20,            // 总电容位数 (Bit 0 ~ Bit 19)
    parameter int WEIGHT_WIDTH  = 30,            // 权重定点数位宽 (Q18.12, 基准 256.0)
    parameter int COMP_WAIT_CYC = 16,            // 比较器/DAC 建立时间 (时钟周期)
    parameter int AVG_LOOPS     = 32,            // 平均次数 (必须为 2 的幂)
    parameter int MAX_CALIB_BIT = 5              // 可信 LSB 段最高位 (Bit 0-5 免校准)
)(
    // --- 全局信号 ---
    input  logic                          clk,
    input  logic                          rst_n,
    
    // --- 控制平面 ---
    input  logic                          start_calib,    // 启动脉冲
    output logic                          calib_done,     // 完成标志
    output logic                          calib_mode_en,  // 状态指示
    
    // --- 模拟前端 (AFE) ---
    input  logic                          comp_out,       // 比较器输出 (1: Vp > Vn)
    input  logic                          comp_valid,     // (预留)
    output logic [CAP_NUM-1:0]            dac_p_force,    // P端 DAC 强制控制
    output logic [CAP_NUM-1:0]            dac_n_force,    // N端 DAC 强制控制
    
    // --- 寄存器堆写回 ---
    output logic                          w_wr_en,
    output logic [4:0]                    w_wr_addr,
    output logic signed [WEIGHT_WIDTH-1:0] w_wr_data
);

    // 计算移位位数: log2(32) = 5
    localparam AVG_SHIFT = $clog2(AVG_LOOPS);

    // =========================================================================
    // 1. 状态机定义 (FSM)
    // =========================================================================
    typedef enum logic [3:0] {
        S_IDLE,           // 空闲状态
        S_INIT_TARGET,    // 初始化目标位，清空累加器
        S_PHASE_P_SETUP,  // P相准备：设置保护位与搜索范围
        S_PHASE_P_SAR,    // P相执行：二分搜索 (Binary Search)
        S_PHASE_N_SETUP,  // N相准备：反向连接
        S_PHASE_N_SAR,    // N相执行：二分搜索
        S_ACCUMULATE,     // 累加操作：Sum += P + N
        S_UPDATE_WEIGHT,  // 更新权重：计算平均并写入 Shadow RAM
        S_DONE            // 校准完成
    } state_t;

    state_t state, next_state;

    // =========================================================================
    // 2. 内部信号声明
    // =========================================================================
    // 控制计数器
    logic [4:0]  target_bit;  // 当前正在校准的目标位 (6~19)
    logic [5:0]  avg_cnt;     // 平均次数计数器
    logic [7:0]  wait_cnt;    // 建立时间计数器
    
    // SAR 核心逻辑
    logic [4:0]         sar_ptr;   // 当前正在试探的位指针
    logic [CAP_NUM-1:0] sar_code;  // SAR 搜索码字 (控制低位 DAC)
    
    // 算术运算单元
    // [Design Note] 累加器位宽需增加 AVG_SHIFT 防止溢出
    logic signed [WEIGHT_WIDTH+AVG_SHIFT+2:0] accumulator;       // 累加器
    logic signed [WEIGHT_WIDTH-1:0]           meas_val_p;        // P相测量结果
    logic signed [WEIGHT_WIDTH-1:0]           meas_val_n;        // N相测量结果
    logic signed [WEIGHT_WIDTH-1:0]           calc_result_wire;  // 平均值计算结果

    // 影子寄存器 (Shadow RAM)
    // [CRITICAL DESIGN] 存储递归算法所需的已知电容权重
    logic signed [WEIGHT_WIDTH-1:0] shadow_weights [CAP_NUM];

    logic comp_out_r;  // 比较器输出打拍同步

    // =========================================================================
    // 3. Shadow RAM 初始化 (Golden Boot)
    // =========================================================================
    // 假设低 6 位 (Bit 0-5) 匹配良好，作为校准基准 (Unit = 256.0)
    initial begin
        for(int i=0; i<CAP_NUM; i++) shadow_weights[i] = 0;
        shadow_weights[0] = 30'd256;      // Bit 0
        shadow_weights[1] = 30'd512;      // Bit 1
        shadow_weights[2] = 30'd1024;     // Bit 2
        shadow_weights[3] = 30'd2048;     // Bit 3
        shadow_weights[4] = 30'd4096;     // Bit 4
        shadow_weights[5] = 30'd8192;     // Bit 5
    end

    // =========================================================================
    // 4. 状态机跳转逻辑
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        // 状态寄存器更新
        if (!rst_n) begin
            state <= S_IDLE;
        end else begin
            state <= next_state;
        end
    end

    always_comb begin
        // 下一状态逻辑判断
        next_state = state;
        case (state)
            S_IDLE:           if (start_calib) next_state = S_INIT_TARGET; else next_state = S_IDLE;
            S_INIT_TARGET:    next_state = S_PHASE_P_SETUP;
            
            // Phase P: Setup -> SAR Loop -> Next
            S_PHASE_P_SETUP:  next_state = S_PHASE_P_SAR;
            S_PHASE_P_SAR:    if (wait_cnt == 0 && sar_ptr == 0) next_state = S_PHASE_N_SETUP; 
                              else next_state = S_PHASE_P_SAR;
            
            // Phase N: Setup -> SAR Loop -> Next
            S_PHASE_N_SETUP:  next_state = S_PHASE_N_SAR;
            S_PHASE_N_SAR:    if (wait_cnt == 0 && sar_ptr == 0) next_state = S_ACCUMULATE;
                              else next_state = S_PHASE_N_SAR;
            
            // 循环与更新判断
            S_ACCUMULATE:     if (avg_cnt == AVG_LOOPS - 1) next_state = S_UPDATE_WEIGHT;
                              else next_state = S_PHASE_P_SETUP;
                              
            S_UPDATE_WEIGHT:  if (target_bit == CAP_NUM - 1) next_state = S_DONE;
                              else next_state = S_INIT_TARGET;
            
            S_DONE:           next_state = S_DONE;
            default:          next_state = S_IDLE;
        endcase
    end

    // =========================================================================
    // 5. 核心数据通路 (Sequential Logic)
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        // 主控制逻辑与数据路径
        if (!rst_n) begin
            calib_done <= 0; calib_mode_en <= 0; target_bit <= MAX_CALIB_BIT + 1;
            avg_cnt <= 0; sar_code <= 0; sar_ptr <= 0; wait_cnt <= 0;
            accumulator <= 0; w_wr_en <= 0; w_wr_addr <= 0; w_wr_data <= 0;
            comp_out_r <= 0; meas_val_p <= 0; meas_val_n <= 0;
        end else begin
            w_wr_en <= 0;
            comp_out_r <= comp_out;  // 输入信号同步

            case (state)
                S_IDLE: begin
                    calib_done <= 0; calib_mode_en <= 0;
                    target_bit <= MAX_CALIB_BIT + 1;  // 从 Bit 6 开始校准
                end
                
                S_INIT_TARGET: begin
                    calib_mode_en <= 1; 
                    accumulator <= 0; 
                    avg_cnt <= 0;
                end

                // =============================================================
                // PHASE P: Target -> P, SAR -> N
                // =============================================================
                S_PHASE_P_SETUP: begin
                    sar_code <= 0;
                    // [Fix] 修复 Bit 20 双重计算问题
                    // 当校准 Bit 18 (Index 17) 或 Bit 19 (Index 18) 时，次高位用于保护，
                    // SAR 搜索需避开该保护位，防止重复计算。
                    if (target_bit == 19)       sar_ptr <= 16;  // [Fix] 修正指针范围
                    else if (target_bit == 18)  sar_ptr <= 16;  // Bit 18 校准时，Bit 17 保护
                    else                        sar_ptr <= target_bit - 1; // 正常情况
                    
                    wait_cnt <= COMP_WAIT_CYC;
                end

                S_PHASE_P_SAR: begin
                    // SAR 逻辑: Wait -> Check -> Update
                    if (wait_cnt == COMP_WAIT_CYC) begin
                         sar_code[sar_ptr] <= 1;  // Set: 试探位置 1
                         wait_cnt <= wait_cnt - 1;
                    end
                    else if (wait_cnt > 0) begin
                         wait_cnt <= wait_cnt - 1;  // Wait: 等待建立
                    end 
                    else begin
                        // Check: 比较器判决
                        // Phase P: 调节 N 端逼近 P 端。Comp=0 (P < N) 表示 N 太大 -> Drop
                        if (!comp_out_r) sar_code[sar_ptr] <= 0; 
                        // Comp=1 (P > N) 表示 N 不够大 -> Keep

                        // 指针移动
                        if (sar_ptr > 0) begin
                            sar_ptr <= sar_ptr - 1;
                            wait_cnt <= COMP_WAIT_CYC;
                        end
                    end
                end

                // =============================================================
                // PHASE N: Target -> N, SAR -> P
                // =============================================================
                S_PHASE_N_SETUP: begin
                    sar_code <= 0;
                    // [Fix] N 相逻辑同步修正，保持与 P 相一致的搜索范围
                    if (target_bit == 19)       sar_ptr <= 16; 
                    else if (target_bit == 18)  sar_ptr <= 16;
                    else                        sar_ptr <= target_bit - 1;
                    wait_cnt <= COMP_WAIT_CYC;
                end

                S_PHASE_N_SAR: begin
                    if (wait_cnt == COMP_WAIT_CYC) begin
                         sar_code[sar_ptr] <= 1;  // Set
                         wait_cnt <= wait_cnt - 1;
                    end
                    else if (wait_cnt > 0) begin
                         wait_cnt <= wait_cnt - 1;  // Wait
                    end 
                    else begin
                        // Check: 比较器判决
                        // Phase N: 调节 P 端逼近 N 端。Comp=1 (P > N) 表示 P 太大 -> Drop
                        if (comp_out_r) sar_code[sar_ptr] <= 0;
                        // Comp=0 (P < N) 表示 P 不够大 -> Keep

                        // 指针移动
                        if (sar_ptr > 0) begin
                            sar_ptr <= sar_ptr - 1;
                            wait_cnt <= COMP_WAIT_CYC;
                        end
                    end
                end

                // =============================================================
                // 结果累加
                // =============================================================
                S_ACCUMULATE: begin
                    // Sum = (Target + Vos) + (Target - Vos) = 2 * Target
                    accumulator <= accumulator + meas_val_p + meas_val_n;
                    avg_cnt <= avg_cnt + 1;
                end

                // =============================================================
                // 结果更新与递归存储
                // =============================================================
                S_UPDATE_WEIGHT: begin
                    // 1. 写回寄存器堆 (供外部读取)
                    w_wr_data <= calc_result_wire;
                    w_wr_addr <= target_bit;
                    w_wr_en   <= 1;
                    
                    // 2. [CRITICAL DESIGN] 写入 Shadow RAM
                    // 这是递归算法的基石，后续高位测量将调用此值。
                    shadow_weights[target_bit] <= calc_result_wire;

                    // 3. 循环控制
                    if (target_bit == CAP_NUM - 1) begin 
                        calib_done <= 1; 
                        calib_mode_en <= 0; 
                    end else begin
                        target_bit <= target_bit + 1;
                    end
                end
            endcase
            
            // [结果锁存] - 在 SAR 结束时刻立即计算 DAC 对应的模拟权重
            if (state == S_PHASE_P_SAR && wait_cnt == 0 && sar_ptr == 0) begin
                meas_val_p <= calc_dac_weight(sar_code);
            end
            if (state == S_PHASE_N_SAR && wait_cnt == 0 && sar_ptr == 0) begin
                meas_val_n <= calc_dac_weight(sar_code);
            end
        end
    end

    // 组合逻辑计算平均值：Accumulator / (2 * Loops)
    assign calc_result_wire = accumulator >>> (AVG_SHIFT + 1);

    // =========================================================================
    // 6. 组合逻辑：DAC 驱动矩阵 (含 MSB 保护)
    // =========================================================================
    always_comb begin
        dac_p_force = 0; dac_n_force = 0;
        
        // --- Phase P: Target on P, SAR on N ---
        if (state == S_PHASE_P_SAR || state == S_PHASE_P_SETUP) begin
            dac_p_force[target_bit] = 1;  // Target 接 P
            dac_n_force = sar_code;       // SAR 接 N
            
            // [MSB Protection Mapping]
            // 强制将保护位接到 N 端 (反向)，压缩差分输入范围
            if (target_bit == 18) dac_n_force[17] = 1; 
            if (target_bit == 19) begin dac_n_force[18] = 1; dac_n_force[17] = 1; end
        end 
        // --- Phase N: Target on N, SAR on P ---
        else if (state == S_PHASE_N_SAR || state == S_PHASE_N_SETUP) begin
            dac_n_force[target_bit] = 1;  // Target 接 N
            dac_p_force = sar_code;       // SAR 接 P
            
            // [MSB Protection Mapping] 反向操作
            if (target_bit == 18) dac_p_force[17] = 1; 
            if (target_bit == 19) begin dac_p_force[18] = 1; dac_p_force[17] = 1; end
        end
    end

    // =========================================================================
    // 7. 函数：计算 DAC 权重 (含 Digital Restoration)
    // =========================================================================
    function automatic logic signed [WEIGHT_WIDTH-1:0] calc_dac_weight(input logic [CAP_NUM-1:0] code);
        logic signed [WEIGHT_WIDTH-1:0] total;
        total = 0;
        
        // 1. 查 Shadow RAM 累加低位
        for (int i = 0; i < CAP_NUM; i++) begin
            if (code[i]) total += shadow_weights[i];
        end
        
        // 2. [Digital Restoration] 数字域恢复被借走的权重
        // 公式: Weight_Target = Weight_SAR + Weight_Protection
        if (target_bit == 18) total += shadow_weights[17];
        if (target_bit == 19) total += shadow_weights[18] + shadow_weights[17];
        
        return total;
    endfunction

endmodule