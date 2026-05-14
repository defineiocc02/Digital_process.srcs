`timescale 1ns/1ps

module virtual_adc_phy #(
    parameter int CAP_NUM = 20
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [CAP_NUM-1:0] dac_p_force,
    input  wire [CAP_NUM-1:0] dac_n_force,
    output reg         comp_out
);

    // Weight array (fully matches MATLAB 16-bit calibration results)
    // Unit: 1 LSB = 256.0
    logic signed [31:0] phy_weights [0:CAP_NUM-1];

    function automatic logic signed [31:0] default_phy_weight(input int bit_idx);
        case (bit_idx)
            0:  default_phy_weight = 32'sd256;       // Bit 1:  1.00
            1:  default_phy_weight = 32'sd512;       // Bit 2:  2.00
            2:  default_phy_weight = 32'sd1024;      // Bit 3:  4.00
            3:  default_phy_weight = 32'sd2048;      // Bit 4:  8.00
            4:  default_phy_weight = 32'sd4096;      // Bit 5:  16.00
            5:  default_phy_weight = 32'sd8192;      // Bit 6:  32.00
            6:  default_phy_weight = 32'sd8584;      // Bit 7:  33.53
            7:  default_phy_weight = 32'sd17165;     // Bit 8:  67.05
            8:  default_phy_weight = 32'sd34330;     // Bit 9:  134.10
            9:  default_phy_weight = 32'sd68659;     // Bit 10: 268.20
            10: default_phy_weight = 32'sd81129;     // Bit 11: 316.91
            11: default_phy_weight = 32'sd81129;     // Bit 12: 316.91
            12: default_phy_weight = 32'sd162255;    // Bit 13: 633.81
            13: default_phy_weight = 32'sd324513;    // Bit 14: 1267.63
            14: default_phy_weight = 32'sd649024;    // Bit 15: 2535.25
            15: default_phy_weight = 32'sd1287959;   // Bit 16: 5031.09
            16: default_phy_weight = 32'sd1287959;   // Bit 17: 5031.09
            17: default_phy_weight = 32'sd2575916;   // Bit 18: 10062.17
            18: default_phy_weight = 32'sd5151834;   // Bit 19: 20124.35
            19: default_phy_weight = 32'sd10303665;  // Bit 20: 40248.69
            default: default_phy_weight = 32'sd0;
        endcase
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i=0; i<CAP_NUM; i++) begin
                phy_weights[i] <= default_phy_weight(i);
            end
        end
    end

    // Voltage accumulation (combinational logic)
    logic signed [39:0] v_p_comb;
    logic signed [39:0] v_n_comb;

    always_comb begin
        v_p_comb = 0;
        v_n_comb = 0;
        for (int i=0; i<CAP_NUM; i++) begin
            if (dac_p_force[i]) v_p_comb = v_p_comb + phy_weights[i];
            if (dac_n_force[i]) v_n_comb = v_n_comb + phy_weights[i];
        end
    end

    // Comparator (sequential logic)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            comp_out <= 1'b0;
        else if ((v_p_comb - v_n_comb + 500) > 0) 
            comp_out <= 1'b1;
        else 
            comp_out <= 1'b0;
    end

endmodule
