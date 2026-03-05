`timescale 1ns/1ps

module flash_decoder_adder (
    // Electrical signal interface (use electrical for actual implementation)
    input  logic [2:0] thermo,  // Input: 3-bit thermometer code
    output logic [1:0] d_flash  // Output: 2-bit binary code
);

    // =========================================================================
    // Core Logic: Adder-based Ones Counter
    // =========================================================================
    // Principle: Directly count how many '1's in the input.
    // 
    // Mapping relationship:
    //   000 (0 ones) -> 00 (0)
    //   001 (1 one)  -> 01 (1)
    //   011 (2 ones) -> 10 (2)
    //   111 (3 ones) -> 11 (3)
    //
    // Bubble Error Suppression:
    //   When input has bubble error like "101" (middle is 0):
    //   1 + 0 + 1 = 2 -> Output 10 (2).
    //   Automatically corrects to nearest valid code (2 ones becomes 2), suppressing bubble errors.
    // =========================================================================

    always_comb begin
        // Use 2'() for bit-width extension to prevent implicit truncation warnings
        d_flash = 2'(thermo[0]) + 2'(thermo[1]) + 2'(thermo[2]);
    end

endmodule
