`timescale 1ns/1ps

module tb_flash_decoder;

    logic [2:0] thermo;
    logic [1:0] d_flash;

    // 实例化 DUT
    flash_decoder_adder dut (.*);

    initial begin
        $display("-------------------------------------------");
        $display(" Thermo In | Binary Out | Case Type");
        $display("-------------------------------------------");

        // 1. 测试正常温度计码
        thermo = 3'b000; #10; $display("    %b    |    %b      | Ideal 0", thermo, d_flash);
        thermo = 3'b001; #10; $display("    %b    |    %b      | Ideal 1", thermo, d_flash);
        thermo = 3'b011; #10; $display("    %b    |    %b      | Ideal 2", thermo, d_flash);
        thermo = 3'b111; #10; $display("    %b    |    %b      | Ideal 3", thermo, d_flash);

        // 2. 测试气泡错误 (Bubble Errors)
        $display("-------------------------------------------");
        // 气泡：中间有个0 (101)。加法器法应输出 2 (10)
        thermo = 3'b101; #10; $display("    %b    |    %b      | Bubble (101->2)", thermo, d_flash);
        
        // 气泡：中间有个1 (010)。加法器法应输出 1 (01)
        thermo = 3'b010; #10; $display("    %b    |    %b      | Bubble (010->1)", thermo, d_flash);
        
        // 气泡：高位单独为1 (100)。加法器法应输出 1 (01)
        thermo = 3'b100; #10; $display("    %b    |    %b      | Bubble (100->1)", thermo, d_flash);

        $display("-------------------------------------------");
        $finish;
    end

endmodule