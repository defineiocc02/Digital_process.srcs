`timescale 1ns/1ps

module virtual_adc_phy #(
    parameter int CAP_NUM = 20
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [19:0] dac_p_force,
    input  wire [19:0] dac_n_force,
    output reg         comp_out
);

    // Weight array (fully matches MATLAB 16-bit calibration results)
    // Unit: 1 LSB = 256.0
    logic signed [31:0] phy_weights [19:0];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Seg 1 (LSB) - Binary
            phy_weights[0]  <= 256;       // Bit 1:  1.00
            phy_weights[1]  <= 512;       // Bit 2:  2.00
            phy_weights[2]  <= 1024;      // Bit 3:  4.00
            phy_weights[3]  <= 2048;      // Bit 4:  8.00
            phy_weights[4]  <= 4096;      // Bit 5:  16.00
            phy_weights[5]  <= 8192;      // Bit 6:  32.00
            
            // Seg 2 - Split Jump
            // MATLAB: 33.53 * 256 = 8583.68 -> 8584
            phy_weights[6]  <= 8584;      // Bit 7:  33.53
            phy_weights[7]  <= 17165;     // Bit 8:  67.05
            phy_weights[8]  <= 34330;     // Bit 9:  134.10
            phy_weights[9]  <= 68659;     // Bit 10: 268.20
            
            // Seg 3
            phy_weights[10] <= 81129;     // Bit 11: 316.91
            phy_weights[11] <= 81129;     // Bit 12: 316.91
            phy_weights[12] <= 162255;    // Bit 13: 633.81
            phy_weights[13] <= 324513;    // Bit 14: 1267.63
            phy_weights[14] <= 649024;    // Bit 15: 2535.25
            
            // Seg 4 (MSB)
            phy_weights[15] <= 1287959;   // Bit 16: 5031.09
            phy_weights[16] <= 1287959;   // Bit 17: 5031.09
            phy_weights[17] <= 2575916;   // Bit 18: 10062.17
            phy_weights[18] <= 5151834;   // Bit 19: 20124.35
            phy_weights[19] <= 10303665;  // Bit 20: 40248.69
        end
    end

    // Voltage accumulation (combinational logic)
    logic signed [39:0] v_p_comb;
    logic signed [39:0] v_n_comb;

    always_comb begin
        v_p_comb = 0;
        v_n_comb = 0;
        for (int i=0; i<20; i++) begin
            if (dac_p_force[i]) v_p_comb = v_p_comb + phy_weights[i];
            if (dac_n_force[i]) v_n_comb = v_n_comb + phy_weights[i];
        end
    end

    // Comparator (sequential logic)
    always_ff @(posedge clk) begin
        if ((v_p_comb - v_n_comb + 500) > 0) 
            comp_out <= 1'b1;
        else 
            comp_out <= 1'b0;
    end

endmodule
