`timescale 1ns/1ps

// =============================================================================
// File Name     : sar_calib_ctrl_serial.sv
// Module Name   : sar_calib_ctrl_serial
// Description   : 高精度 Split-Sampling SAR ADC 前台递归校准控制器 (串行版)
//
// Functionality :
//   实现基于 "Measure-then-Set" 策略的递归校准算法。利用低位已校准电容（存储
//   在 Shadow RAM 中）作为参考 DAC，通过二分搜索测量高位电容的实际权重。
//   v2.0 引入串行计算架构以优化时序，并增强 ASIC 复位可靠性。
//
// Key Features  :
//   1. 递归测量 (Recursive Measurement): 利用低位组合测量高位
//   2. 串行累加 (Serial Accumulation): [v2.0 New] 多周期权重计算，消除组合逻辑时序瓶颈
//   3. 失调消除 (Offset Cancellation): 采用 (P+N)/2 差分测量法
//   4. MSB 保护 (MSB Protection): 强制反接次高位以压缩共模范围，并在数字域补偿
//   5. ASIC复位 (ASIC Safe Reset): [v2.0 New] 同步复位加载基准权重，替代 initial 块
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
//   1. [CRITICAL] 针对 Bit 18/19 的校准启用了特殊保护逻辑 (Bit-Swapping)
//   2. [TIMING]   权重计算拆分为 S_PHASE_x_CALC 状态，需消耗 CAP_NUM 个时钟周期
//   3. [ASIC]     复位释放后，Shadow RAM 低位自动加载理想值
// =============================================================================

module sar_calib_ctrl_serial #(
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
        S_INIT_TARGET,    // 初始化目标位
        
        // P 相序列
        S_PHASE_P_SETUP,  // P相准备：设置保护位与搜索范围
        S_PHASE_P_SAR,    // P相执行：二分搜索 (Binary Search)
        S_PHASE_P_CALC,   // P相计算：[v2.0 New] 串行累加权重
        
        // N 相序列
        S_PHASE_N_SETUP,  // N相准备：反向连接
        S_PHASE_N_SAR,    // N相执行：二分搜索
        S_PHASE_N_CALC,   // N相计算：[v2.0 New] 串行累加权重
        
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
    logic [4:0]             sar_ptr;   // 当前正在试探的位指针
    logic [CAP_NUM-1:0]     sar_code;  // SAR 搜索码字
    
    // 串行计算逻辑 [v2.0 New]
    logic [4:0]             calc_cnt;  // 串行累加计数器
    logic signed [WEIGHT_WIDTH+5:0] temp_acc; // 临时累加器 (防溢出)
    
    // 算术运算单元
    logic signed [WEIGHT_WIDTH+AVG_SHIFT+2:0] accumulator;        // 总平均累加器
    logic signed [WEIGHT_WIDTH-1:0]           meas_val_p;         // P相测量结果
    logic signed [WEIGHT_WIDTH-1:0]           meas_val_n;         // N相测量结果
    logic signed [WEIGHT_WIDTH-1:0]           calc_result_wire;   // 平均值计算结果

    // 影子寄存器 (Shadow RAM)
    // [CRITICAL] 存储递归算法所需的已知电容权重
    logic signed [WEIGHT_WIDTH-1:0] shadow_weights [CAP_NUM];

    logic comp_out_r;  // 比较器输出打拍同步

    // =========================================================================
    // 3. 状态机跳转逻辑
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= S_IDLE;
        else        state <= next_state;
    end

    always_comb begin
        next_state = state;
        case (state)
            S_IDLE:           if (start_calib) next_state = S_INIT_TARGET; else next_state = S_IDLE;
            S_INIT_TARGET:    next_state = S_PHASE_P_SETUP;
            
            // Phase P: Setup -> SAR Loop -> Calc Loop -> Next
            S_PHASE_P_SETUP:  next_state = S_PHASE_P_SAR;
            S_PHASE_P_SAR:    if (wait_cnt == 0 && sar_ptr == 0) next_state = S_PHASE_P_CALC; 
                              else next_state = S_PHASE_P_SAR;
            S_PHASE_P_CALC:   if (calc_cnt == CAP_NUM) next_state = S_PHASE_N_SETUP; // 等待串行计算完成
                              else next_state = S_PHASE_P_CALC;
            
            // Phase N: Setup -> SAR Loop -> Calc Loop -> Next
            S_PHASE_N_SETUP:  next_state = S_PHASE_N_SAR;
            S_PHASE_N_SAR:    if (wait_cnt == 0 && sar_ptr == 0) next_state = S_PHASE_N_CALC; 
                              else next_state = S_PHASE_N_SAR;
            S_PHASE_N_CALC:   if (calc_cnt == CAP_NUM) next_state = S_ACCUMULATE;    // 等待串行计算完成

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
    // 4. 核心数据通路 (Sequential Logic)
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            calib_done <= 0; calib_mode_en <= 0; target_bit <= MAX_CALIB_BIT + 1;
            avg_cnt <= 0; sar_code <= 0; sar_ptr <= 0; wait_cnt <= 0;
            accumulator <= 0; w_wr_en <= 0; w_wr_addr <= 0; w_wr_data <= 0;
            comp_out_r <= 0; meas_val_p <= 0; meas_val_n <= 0;
            calc_cnt <= 0; temp_acc <= 0;
            
            // [ASIC Safe Initialization]
            // 在复位阶段初始化基准权重，替代原有的 initial 块，确保 ASIC 兼容性
            for(int i=0; i<CAP_NUM; i++) shadow_weights[i] <= 0;
            shadow_weights[0] <= 30'd256;  // Bit 0 = 1.0
            shadow_weights[1] <= 30'd512;  // Bit 1 = 2.0
            shadow_weights[2] <= 30'd1024;
            shadow_weights[3] <= 30'd2048;
            shadow_weights[4] <= 30'd4096;
            shadow_weights[5] <= 30'd8192; // Bit 5 = 32.0
            
        end else begin
            w_wr_en <= 0;
            comp_out_r <= comp_out; // 输入同步

            case (state)
                S_IDLE: begin
                    calib_done <= 0; calib_mode_en <= 0;
                    target_bit <= MAX_CALIB_BIT + 1;
                end
                
                S_INIT_TARGET: begin
                    calib_mode_en <= 1; accumulator <= 0; avg_cnt <= 0;
                end

                // =============================================================
                // PHASE P: SAR Search -> Serial Calc
                // =============================================================
                S_PHASE_P_SETUP: begin
                    sar_code <= 0;
                    // [MSB Protection] 避开保护位，防止重复计算
                    if (target_bit >= 18) sar_ptr <= 16; else sar_ptr <= target_bit - 1;
                    wait_cnt <= COMP_WAIT_CYC;
                end

                S_PHASE_P_SAR: begin
                    if (wait_cnt == COMP_WAIT_CYC) begin
                         sar_code[sar_ptr] <= 1; wait_cnt <= wait_cnt - 1; // Trial
                    end else if (wait_cnt > 0) begin
                         wait_cnt <= wait_cnt - 1;
                    end else begin
                        if (!comp_out_r) sar_code[sar_ptr] <= 0; // Drop if P > N
                        if (sar_ptr > 0) begin
                            sar_ptr <= sar_ptr - 1; wait_cnt <= COMP_WAIT_CYC;
                        end else begin
                            calc_cnt <= 0; temp_acc <= 0; // SAR 结束，启动串行计算
                        end
                    end
                end

                S_PHASE_P_CALC: begin
                    if (calc_cnt < CAP_NUM) begin
                        // [Serial Accumulation] 逐位累加，优化时序
                        if (sar_code[calc_cnt]) temp_acc <= temp_acc + shadow_weights[calc_cnt];
                        calc_cnt <= calc_cnt + 1;
                    end else begin
                        // [Digital Restoration] 补偿保护位权重
                        automatic logic signed [WEIGHT_WIDTH+5:0] final_val = temp_acc;
                        if (target_bit == 18) final_val += shadow_weights[17];
                        if (target_bit == 19) final_val += shadow_weights[18] + shadow_weights[17];
                        meas_val_p <= signed'(final_val[WEIGHT_WIDTH-1:0]);
                    end
                end

                // =============================================================
                // PHASE N: SAR Search -> Serial Calc
                // =============================================================
                S_PHASE_N_SETUP: begin
                    sar_code <= 0;
                    if (target_bit >= 18) sar_ptr <= 16; else sar_ptr <= target_bit - 1;
                    wait_cnt <= COMP_WAIT_CYC;
                end

                S_PHASE_N_SAR: begin
                    if (wait_cnt == COMP_WAIT_CYC) begin
                         sar_code[sar_ptr] <= 1; wait_cnt <= wait_cnt - 1;
                    end else if (wait_cnt > 0) begin
                         wait_cnt <= wait_cnt - 1;
                    end else begin
                        if (comp_out_r) sar_code[sar_ptr] <= 0; // Drop if N > P (Inverse logic)
                        if (sar_ptr > 0) begin
                            sar_ptr <= sar_ptr - 1; wait_cnt <= COMP_WAIT_CYC;
                        end else begin
                            calc_cnt <= 0; temp_acc <= 0;
                        end
                    end
                end

                S_PHASE_N_CALC: begin
                    if (calc_cnt < CAP_NUM) begin
                        if (sar_code[calc_cnt]) temp_acc <= temp_acc + shadow_weights[calc_cnt];
                        calc_cnt <= calc_cnt + 1;
                    end else begin
                        // [Digital Restoration] 补偿保护位权重
                        automatic logic signed [WEIGHT_WIDTH+5:0] final_val = temp_acc;
                        if (target_bit == 18) final_val += shadow_weights[17];
                        if (target_bit == 19) final_val += shadow_weights[18] + shadow_weights[17];
                        meas_val_n <= signed'(final_val[WEIGHT_WIDTH-1:0]);
                    end
                end

                // =============================================================
                // 结果累加与更新
                // =============================================================
                S_ACCUMULATE: begin
                    accumulator <= accumulator + meas_val_p + meas_val_n;
                    avg_cnt <= avg_cnt + 1;
                end

                S_UPDATE_WEIGHT: begin
                    // 1. 写回外部接口
                    w_wr_data <= calc_result_wire;
                    w_wr_addr <= target_bit;
                    w_wr_en   <= 1;
                    
                    // 2. [CRITICAL] 更新 Shadow RAM，供下一位递归使用
                    shadow_weights[target_bit] <= calc_result_wire;
                    
                    if (target_bit == CAP_NUM - 1) begin 
                        calib_done <= 1; calib_mode_en <= 0; 
                    end else begin
                        target_bit <= target_bit + 1;
                    end
                end
            endcase
        end
    end

    // [Optimization] 采用四舍五入 (Rounding) 替代向下截断，减少递归累积误差
    // formula: (accumulator + 0.5) >> shift
    assign calc_result_wire = (accumulator + (1 << AVG_SHIFT)) >>> (AVG_SHIFT + 1);

    // =========================================================================
    // 5. 组合逻辑：DAC 驱动矩阵 (含 MSB 保护)
    // =========================================================================
    always_comb begin
        dac_p_force = 0; dac_n_force = 0;
        
        // --- Phase P Drive ---
        if (state == S_PHASE_P_SAR || state == S_PHASE_P_SETUP || state == S_PHASE_P_CALC) begin
            dac_p_force[target_bit] = 1; 
            dac_n_force = sar_code;       
            // [MSB Protection Mapping]
            if (target_bit == 18) dac_n_force[17] = 1; 
            if (target_bit == 19) begin dac_n_force[18] = 1; dac_n_force[17] = 1; end
        end 
        // --- Phase N Drive ---
        else if (state == S_PHASE_N_SAR || state == S_PHASE_N_SETUP || state == S_PHASE_N_CALC) begin
            dac_n_force[target_bit] = 1; 
            dac_p_force = sar_code;       
            // [MSB Protection Mapping]
            if (target_bit == 18) dac_p_force[17] = 1; 
            if (target_bit == 19) begin dac_p_force[18] = 1; dac_p_force[17] = 1; end
        end
    end

endmodule