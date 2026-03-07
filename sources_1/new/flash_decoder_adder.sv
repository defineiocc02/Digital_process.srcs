`timescale 1ns/1ps

module flash_decoder_adder (
    // Port signal interface (no electrical type used)
    input  logic [2:0] thermo,  // Input: 3-bit thermometer code
    output logic [1:0] d_flash  // Output: 2-bit binary result
);

    // =========================================================================
    // Core Logic: Ones Counter
    // =========================================================================
    // Principle: Directly count how many '1's in the input.
    // 
    // Mapping relationship:
    //   000 (0 ones) -> 00 (0)
    //   001 (1 ones) -> 01 (1)
    //   011 (2 ones) -> 10 (2)
    //   111 (3 ones) -> 11 (3)
    //
    // Bubble Error Suppression:
    //   Example: Input has bubble error "101" (middle bit 0):
    //   1 + 0 + 1 = 2 -> Output 10 (2).
    //   This automatically treats bubble as nearest valid code (2 ones = 2),
    //   achieving error correction.
    // =========================================================================

    always_comb begin
        // Use 2'() for width casting to prevent synthesis tool warnings about width mismatch in addition
        d_flash = 2'(thermo[0]) + 2'(thermo[1]) + 2'(thermo[2]);
    end

endmodule
