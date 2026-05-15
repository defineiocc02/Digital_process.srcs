`timescale 1ns/1ps

/**
 * =============================================================================
 * Module:       sar_adc_fpga_top
 * Description:  16-bit Split-Sampling SAR ADC Digital Backend Top.
 * 
 * Standards:    IEEE 1800-2017
 * Features:     SRM Linearization, Clock Gating, Operand Isolation
 * =============================================================================
 */

module sar_adc_fpga_top #(
    parameter int CAP_NUM        = 20, 
    parameter int WEIGHT_WIDTH   = 28, 
    parameter int OUTPUT_WIDTH   = 16,
    parameter bit EMULATION_MODE = 1,  
    parameter int SRM_SAMPLES    = 32,
    parameter int FRAC_BITS      = 4   
)(
    input  wire         clk,             
    input  wire         rst_n,            
    input  wire         start_calib,      
    
    // Hardware Interface
    input  wire [CAP_NUM-1:0] sar_bits_i,       
    input  wire               sar_ready_i,      
    input  wire               comp_out_i,       
    
    // Outputs
    output wire                calib_done, 
    output wire [OUTPUT_WIDTH-1:0] adc_data,    
    output wire                data_valid
);

    logic core_start_req, calib_mode_en;
    logic sar_ready_int, conversion_done_int;
    logic [CAP_NUM-1:0] dac_p_force, dac_n_force;
    logic [CAP_NUM-1:0] sar_bits_int;
    logic [7:0] srm_counter_int;
    
    logic [WEIGHT_WIDTH-1:0] w_wr_data;
    logic [4:0]              w_wr_addr;
    logic                    w_wr_en;

    // --- Reset & Sync ---
    logic rst_n_sync, rst_n_meta;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin rst_n_meta <= 0; rst_n_sync <= 0; end
        else        begin rst_n_meta <= 1; rst_n_sync <= rst_n_meta; end
    end

    logic start_calib_sync, start_calib_d;
    always_ff @(posedge clk or negedge rst_n_sync) begin
        if (!rst_n_sync) {start_calib_sync, start_calib_d} <= '0;
        else             {start_calib_sync, start_calib_d} <= {start_calib_d, start_calib};
    end

    // --- Low Power Control ---
    logic calib_active_r;
    always_ff @(posedge clk or negedge rst_n_sync) begin
        if (!rst_n_sync) calib_active_r <= 1'b1;
        else begin
            if (start_calib_sync) calib_active_r <= 1'b1;
            else if (calib_done)  calib_active_r <= 1'b0;
        end
    end

    wire clk_calib_gated;
    // Xilinx Primitive (Use clk_calib_gated = clk & calib_active_r for generic sim)
    BUFGCE u_clk_gate (.O(clk_calib_gated), .I(clk), .CE(calib_active_r));

    // --- SRM LUT ---
    logic [7:0] srm_lut_index_r;
    always_ff @(posedge clk or negedge rst_n_sync) begin
        if (!rst_n_sync) srm_lut_index_r <= 8'd128;
        else if (!calib_done) srm_lut_index_r <= srm_counter_int;
    end

    `include "erf_inv_lut.vh"
    wire signed [WEIGHT_WIDTH-1:0] srm_residue_ext;
    assign srm_residue_ext = {{ (WEIGHT_WIDTH-8){erf_lut[srm_lut_index_r][7]} }, erf_lut[srm_lut_index_r]} <<< FRAC_BITS;

    // --- Modules ---
    sar_calib_ctrl #(
        .CAP_NUM(CAP_NUM), .WEIGHT_WIDTH(WEIGHT_WIDTH), .FRAC_BITS(FRAC_BITS)
    ) u_ctrl (
        .clk(clk_calib_gated), .rst_n(rst_n_sync),
        .start_calib(start_calib_sync),
        .sar_ready(sar_ready_int), .conversion_done(conversion_done_int),    
        .srm_residue_val(srm_residue_ext), .sar_code(16'd0),                  
        .calib_done(calib_done),
        .core_start_req(core_start_req), .calib_mode_en(calib_mode_en),
        .dac_p_force(dac_p_force), .dac_n_force(dac_n_force),
        .w_wr_en(w_wr_en), .w_wr_addr(w_wr_addr), .w_wr_data(w_wr_data)
    );

    sar_reconstruction #(
        .CAP_NUM(CAP_NUM), .WEIGHT_WIDTH(WEIGHT_WIDTH), .OUTPUT_WIDTH(OUTPUT_WIDTH),
        .DAC_ARCH(1), .FRAC_BITS(FRAC_BITS)
    ) u_recon (
        .clk(clk), .rst_n(rst_n_sync),
        .data_valid_in(sar_ready_int && !calib_mode_en),
        .raw_bits(sar_bits_int),
        .w_wr_en(w_wr_en), .w_wr_addr(w_wr_addr), .w_wr_data(w_wr_data),
        .srm_residue(srm_residue_ext),
        .data_valid_out(data_valid), .adc_dout(adc_data)
    );

    // --- Model Mux ---
    generate
        if (EMULATION_MODE) begin : gen_emulation
            sar_adc_model #(.CAP_NUM(CAP_NUM)) u_model (
                .clk(clk), .rst_n(rst_n_sync),
                .core_start_req(core_start_req),
                .dac_p_force(dac_p_force), .dac_n_force(dac_n_force),
                .sar_ready(sar_ready_int), .conversion_done(conversion_done_int),
                .sar_bits(sar_bits_int), .sar_code(), .srm_counter(srm_counter_int)
            );
        end else begin : gen_hw
            logic [7:0] hw_srm_cnt_raw; 
            logic [5:0] sample_idx;
            logic       counting_en;
            always_ff @(posedge clk or negedge rst_n_sync) begin
                if (!rst_n_sync) begin
                    {hw_srm_cnt_raw, sample_idx, counting_en, sar_ready_int, conversion_done_int} <= 0;
                end else begin
                    {sar_ready_int, conversion_done_int} <= 0;
                    if (core_start_req) begin
                        {hw_srm_cnt_raw, sample_idx} <= 0; counting_en <= 1;
                    end else if (counting_en) begin
                        if (comp_out_i) hw_srm_cnt_raw <= hw_srm_cnt_raw + 1;
                        if (sample_idx == SRM_SAMPLES-1) begin
                            counting_en <= 0; {conversion_done_int, sar_ready_int} <= 2'b11;
                        end else sample_idx <= sample_idx + 1;
                    end
                end
            end
            assign srm_counter_int = {hw_srm_cnt_raw[4:0], 3'b000}; 
            assign sar_bits_int = sar_bits_i;
        end
    endgenerate
endmodule