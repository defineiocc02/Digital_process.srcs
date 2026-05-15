`timescale 1ns/1ps

module sar_adc_model #(parameter int CAP_NUM = 20)(
    input  wire         clk, rst_n, core_start_req, 
    input  wire [CAP_NUM-1:0] dac_p_force, dac_n_force,
    output logic        sar_ready, conversion_done,
    output logic [CAP_NUM-1:0] sar_bits,
    output logic signed [15:0] sar_code,
    output logic [7:0] srm_counter
);

    localparam int SCALE = 16; 
    int phys_weights [0:19];
    int v_dac_diff, noise_int; 
    typedef enum logic [1:0] {M_IDLE, M_CONV, M_DONE} model_state_t;
    model_state_t state;
    logic [5:0] conv_cnt; 

    // Weights validated by cap_array_calib_16b.m
    initial begin
        phys_weights[0]=16;    phys_weights[1]=32;    phys_weights[2]=64;    
        phys_weights[3]=128;   phys_weights[4]=256;   phys_weights[5]=512;
        phys_weights[6]=536;   
        phys_weights[7]=1073;  phys_weights[8]=2146;  phys_weights[9]=4291;  
        phys_weights[10]=5071; phys_weights[11]=5071; 
        phys_weights[12]=10141; phys_weights[13]=20282; phys_weights[14]=40564; 
        phys_weights[15]=80497; phys_weights[16]=80497; phys_weights[17]=160995; 
        phys_weights[18]=321990; phys_weights[19]=643979;
    end

    always_comb begin
        automatic int sum_p = 0; automatic int sum_n = 0;
        for (int k=0; k<CAP_NUM; k++) begin
            if (dac_p_force[k]) sum_p += phys_weights[k];
            if (dac_n_force[k]) sum_n += phys_weights[k];
        end
        v_dac_diff = sum_p - sum_n;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= M_IDLE; {conv_cnt, sar_ready, conversion_done, srm_counter} <= 0;
        end else begin
            case (state)
                M_IDLE: begin
                    {conversion_done, sar_ready} <= 0;
                    if (core_start_req) begin state <= M_CONV; conv_cnt <= 0; end
                end
                M_CONV: begin
                    if (conv_cnt == 20) begin
                        noise_int = 0; 
                        begin
                            automatic int ideal_count_scaled, final_count;
                            ideal_count_scaled = (128 * SCALE) + v_dac_diff + noise_int;
                            final_count = ideal_count_scaled / SCALE;
                            if (final_count > 255) final_count = 255;
                            if (final_count < 0)   final_count = 0;
                            srm_counter <= final_count[7:0];
                        end
                        state <= M_DONE; conv_cnt <= 0;
                    end else conv_cnt <= conv_cnt + 1;
                end
                M_DONE: begin
                    sar_ready <= 1; conversion_done <= 1;
                    if (conv_cnt == 2) state <= M_IDLE; else conv_cnt <= conv_cnt + 1;
                end
            endcase
        end
    end
endmodule