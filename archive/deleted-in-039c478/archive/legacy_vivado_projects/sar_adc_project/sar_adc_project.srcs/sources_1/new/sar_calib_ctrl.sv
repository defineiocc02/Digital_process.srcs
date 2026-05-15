`timescale 1ns/1ps

// =============================================================================
// Module Name   : sar_calib_ctrl
// Version       : 22.0 (Golden Release - Sub-SAR Architecture)
// Author        : Mixed-Signal IC Architect
// Description   : Split-Sampling SAR ADC 前台校准控制器
//
// 核心原理:
//    利用 LSB DAC (Bit 0-5) 作为量化器，测量高位电容 (Target Bit) 
//    与中间位组合 (Intermediate Mask) 之间的残差电压。
//    Weight_Target = Sum(Weight_Intermediate) + Measured_Residue_Code * LSB_Unit
// =============================================================================

module sar_calib_ctrl #(
    parameter int CAP_NUM       = 20,       
    parameter int WEIGHT_WIDTH  = 30,       // 定点数 Q22.8
    parameter int COMP_WAIT_CYC = 16,       // 比较器建立时间
    parameter int AVG_LOOPS     = 32,       // 平均次数 (用于抑制随机噪声)
    parameter int MAX_CALIB_BIT = 5         // 用于测量残差的 LSB DAC 位宽 (0-5)
)(
    // --- 时钟与复位 ---
    input  logic                          clk,
    input  logic                          rst_n,

    // --- 控制接口 ---
    input  logic                          start_calib, // 启动脉冲
    output logic                          calib_done,  // 校准完成标志

    // --- AFE 模拟前端接口 ---
    input  logic                          comp_out,    // 比较器输出
    input  logic                          comp_valid,  // 比较器有效
    output logic                          calib_mode_en, // 校准模式使能
    output logic [CAP_NUM-1:0]            dac_p_force,   // DAC P端 强制控制
    output logic [CAP_NUM-1:0]            dac_n_force,   // DAC N端 强制控制

    // --- 权重写入接口 (RAM Update) ---
    output logic                          w_wr_en,
    output logic [4:0]                    w_wr_addr,
    output logic [WEIGHT_WIDTH-1:0]       w_wr_data
);

    // =========================================================================
    // 1. 状态机定义
    // =========================================================================
    typedef enum logic [4:0] {
        S_IDLE, 
        S_PREPARE,
        
        // --- 测量循环 ---
        S_MEASURE_INIT, // 初始化累加器
        S_SAR_INIT,     // 初始化 Sub-SAR 搜索
        S_SAR_WAIT,     // 等待 DAC 建立
        S_SAR_DECIDE,   // 比较器判决与逻辑更新
        S_ACCUMULATE,   // 累加单次测量结果
        
        S_UPDATE_RAM,   // 更新权重 RAM
        S_DONE
    } state_t;

    state_t state, next_state;

    // =========================================================================
    // 2. 内部寄存器
    // =========================================================================
    // 权重存储 RAM
    logic signed [WEIGHT_WIDTH-1:0] weight_ram [0:CAP_NUM-1];
    
    // 累加器：用于 AVG_LOOPS 次测量的平均
    logic signed [15:0]             accum_sar_code; 
    logic [5:0]                     avg_cnt;
    
    // 控制寄存器
    logic [4:0]           target_bit;       // 当前正在校准的位 (6 to 19)
    logic [4:0]           sar_bit_idx;      // Sub-SAR 当前搜索位 (5 down to 0)
    
    // Sub-SAR 寄存器 (保存 Bit 0-5 的 DAC 状态)
    logic [MAX_CALIB_BIT:0] sar_code_reg;   
    
    // 延时计数器
    logic [7:0]             wait_cnt;

    // CDC (跨时钟域同步)
    logic comp_out_s, comp_valid_s;
    logic [1:0] co_r, cv_r;

    // =========================================================================
    // 3. 组合逻辑计算核心
    // =========================================================================
    logic [CAP_NUM-1:0]             calc_intermediate_mask;
    logic signed [WEIGHT_WIDTH-1:0] calc_sum_mask;
    logic signed [WEIGHT_WIDTH-1:0] calc_avg_sar_code;
    logic signed [WEIGHT_WIDTH-1:0] calc_final_weight;
    
    always_comb begin
        // A. 中间位掩码逻辑 (Intermediate Mask)
        // 根据 Split-Sampling 物理结构，硬编码每位的对冲电容
        calc_intermediate_mask = '0;
        case (target_bit)
            7, 8, 9:        for (int k=6; k<target_bit; k++) calc_intermediate_mask[k] = 1'b1;
            10:             calc_intermediate_mask[9] = 1'b1;  
            11:             calc_intermediate_mask[10] = 1'b1; 
            12, 13, 14, 15: for (int k=10; k<target_bit; k++) calc_intermediate_mask[k] = 1'b1;
            16:             calc_intermediate_mask[15] = 1'b1; 
            17:             begin calc_intermediate_mask[15] = 1'b1; calc_intermediate_mask[16] = 1'b1; end
            18:             begin calc_intermediate_mask[15] = 1'b1; calc_intermediate_mask[16] = 1'b1; end
            19:             begin calc_intermediate_mask[15] = 1'b1; calc_intermediate_mask[16] = 1'b1; end
            default:        calc_intermediate_mask = '0;
        endcase

        // B. 计算基准权重和 (Sum of Intermediate Weights)
        // 注意：这里只累加中间位，不累加任何"搜索结果"，彻底避免 Double Counting
        calc_sum_mask = 0;
        for (int i=0; i<CAP_NUM; i++) begin
            if (calc_intermediate_mask[i]) calc_sum_mask += weight_ram[i];
        end

        // C. 处理 SAR 测量结果
        // accum_sar_code 是多次测量的 LSB Code 之和
        // 计算平均值并转换为权重格式 (Q22.8)
        // 假设 Unit Weight (Bit 0) ≈ 256.0
        // 公式: (Accum >> log2(AVG)) * 256
        // 这里 AVG=32 (shift 5), *256 (shift 8) -> Net result: Accum << 3
        calc_avg_sar_code = (accum_sar_code >>> 5) * 256; 

        // D. 最终权重重建
        // Weight = Mask_Sum + Measured_Residue + Redundancy(if any)
        if (target_bit == 18)      
            calc_final_weight = calc_sum_mask + calc_avg_sar_code + weight_ram[17];
        else if (target_bit == 19) 
            calc_final_weight = calc_sum_mask + calc_avg_sar_code + weight_ram[18] + weight_ram[17];
        else                       
            calc_final_weight = calc_sum_mask + calc_avg_sar_code;
    end

    // =========================================================================
    // 4. 输入同步与 RAM 初始化
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            co_r <= 0; comp_out_s <= 0;
            cv_r <= 0; comp_valid_s <= 0;
        end else begin
            co_r <= {co_r[0], comp_out}; comp_out_s <= co_r[1];
            cv_r <= {cv_r[0], comp_valid}; comp_valid_s <= cv_r[1];
        end
    end

    // 理想权重初始化 (仿真模型)
    initial begin
        weight_ram[0] = 30'd256;      weight_ram[1] = 30'd512;
        weight_ram[2] = 30'd1024;     weight_ram[3] = 30'd2048;
        weight_ram[4] = 30'd4096;     weight_ram[5] = 30'd8192;
        weight_ram[6] = 30'd8583;     
        weight_ram[7] = 30'd17165;    weight_ram[8] = 30'd34330;
        weight_ram[9] = 30'd68659;    weight_ram[10]= 30'd81129;
        weight_ram[11]= 30'd81129;    weight_ram[12]= 30'd162255;
        weight_ram[13]= 30'd324513;   weight_ram[14]= 30'd649024;
        weight_ram[15]= 30'd1287959;  weight_ram[16]= 30'd1287959;
        weight_ram[17]= 30'd2575916;  weight_ram[18]= 30'd5151834;
        weight_ram[19]= 30'd10303665;
    end

    // =========================================================================
    // 5. 主状态机 (3-Process FSM)
    // =========================================================================
    // 5.1 状态跳转
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= S_IDLE;
        else        state <= next_state;
    end

    // 5.2 下一状态逻辑
    always_comb begin
        next_state = state; 
        case (state)
            S_IDLE:          if (start_calib) next_state = S_PREPARE;
            S_PREPARE:       next_state = S_MEASURE_INIT;

            // 测量初始化
            S_MEASURE_INIT:  next_state = S_SAR_INIT;
            
            // Sub-SAR 二分搜索循环
            S_SAR_INIT:      next_state = S_SAR_WAIT;
            S_SAR_WAIT:      if (wait_cnt == 0) next_state = S_SAR_DECIDE;
            S_SAR_DECIDE:    if (comp_valid_s) begin
                                if (sar_bit_idx == 0) next_state = S_ACCUMULATE;
                                else                  next_state = S_SAR_INIT; 
                             end
            
            // 累加平均
            S_ACCUMULATE:    if (avg_cnt == AVG_LOOPS - 1) next_state = S_UPDATE_RAM;
                             else                          next_state = S_MEASURE_INIT; 
            
            // 更新权重与循环
            S_UPDATE_RAM:    if (target_bit == CAP_NUM - 1) next_state = S_DONE;
                             else                           next_state = S_PREPARE;
            S_DONE:          next_state = S_DONE;
        endcase
    end

    // 5.3 数据通路逻辑
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            calib_done <= 0; calib_mode_en <= 0;
            target_bit <= 6; 
            wait_cnt <= 0; 
            w_wr_en <= 0; w_wr_addr <= 0; w_wr_data <= 0;
            accum_sar_code <= 0; avg_cnt <= 0;
            sar_bit_idx <= 0; sar_code_reg <= 0;
        end else begin
            w_wr_en <= 0;
            if (wait_cnt > 0) wait_cnt <= wait_cnt - 1;

            case (state)
                S_IDLE: begin
                    calib_done <= 0;
                    if (start_calib) begin
                        calib_mode_en <= 1;
                        target_bit    <= 6; 
                    end
                end

                S_PREPARE: begin
                    wait_cnt <= COMP_WAIT_CYC;
                end

                S_MEASURE_INIT: begin
                    // 初始化 Sub-SAR 逻辑
                    sar_code_reg    <= 0;
                    sar_code_reg[MAX_CALIB_BIT] <= 1; // 置位 MSB (Binary Search 算法)
                    sar_bit_idx     <= MAX_CALIB_BIT;
                    
                    // 如果是新的平均周期，清除累加器
                    if (state == S_PREPARE) begin
                        accum_sar_code  <= 0;
                        avg_cnt         <= 0;
                    end
                    wait_cnt <= COMP_WAIT_CYC;
                end

                S_SAR_INIT: begin
                   wait_cnt <= COMP_WAIT_CYC;
                end
                
                S_SAR_DECIDE: begin
                    if (comp_valid_s) begin
                        // 标准 Binary Search 逻辑:
                        // 如果 Comp=0 (N端电压过大)，清除当前位
                        if (comp_out_s == 0) sar_code_reg[sar_bit_idx] <= 0; 
                        
                        // 移向下一位
                        if (sar_bit_idx > 0) begin
                            sar_bit_idx <= sar_bit_idx - 1;
                            sar_code_reg[sar_bit_idx - 1] <= 1; // 预置下一位
                        end
                    end
                end

                S_ACCUMULATE: begin
                    // 将本次测得的 Code 累加 (转换为有符号数)
                    accum_sar_code <= accum_sar_code + signed'({10'b0, sar_code_reg});
                    if (avg_cnt != AVG_LOOPS - 1) begin
                        avg_cnt <= avg_cnt + 1;
                    end
                end

                S_UPDATE_RAM: begin
                    weight_ram[target_bit] <= calc_final_weight;
                    w_wr_en <= 1; w_wr_addr <= target_bit; w_wr_data <= calc_final_weight;
                    
                    // 重置累加器，准备下一个 Target Bit
                    accum_sar_code <= 0;
                    avg_cnt        <= 0;

                    if (target_bit == CAP_NUM - 1) begin
                        calib_done <= 1; calib_mode_en <= 0;
                    end else begin
                        target_bit <= target_bit + 1;
                    end
                end
            endcase
        end
    end

    // =========================================================================
    // 6. DAC 输出驱动逻辑
    // =========================================================================
    logic [CAP_NUM-1:0] sar_dac_map;
    // 将 Sub-SAR 的 6位 Code 映射到 DAC 的低 6位
    assign sar_dac_map = {{(CAP_NUM-MAX_CALIB_BIT-1){1'b0}}, sar_code_reg};

    always_comb begin
        dac_p_force = '0; dac_n_force = '0;
        if (calib_mode_en) begin
            // ------------------------------------
            // P 端：强制 Target Bit
            // ------------------------------------
            if (target_bit == 18) begin 
                dac_p_force[18]=1; 
                dac_n_force[17]=1; 
            end else if (target_bit == 19) begin 
                dac_p_force[19]=1; 
                dac_n_force[18]=1; dac_n_force[17]=1; 
            end else begin 
                dac_p_force[target_bit] = 1; 
            end
            
            // ------------------------------------
            // N 端：强制 Intermediate Mask + Sub-SAR
            // ------------------------------------
            dac_n_force |= calc_intermediate_mask; 
            // 关键：LSB DAC 参与测量，量化残差
            dac_n_force |= sar_dac_map; 
        end
    end

endmodule