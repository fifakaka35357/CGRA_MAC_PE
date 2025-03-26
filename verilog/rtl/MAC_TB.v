`timescale 1ns / 1ps

module Combinational_MAC_Pure_tb;
    // Test signals declaration
    reg [7:0] alu;          // Operation code
    reg signed_;            // Signed/unsigned flag (still unused by DUT)
    reg signed [15:0] a;    // Input data
    reg signed [15:0] b;    // Weight data
    reg d;                  // Extra control signal (unused by DUT logic)
    wire [15:0] O0;         // 16-bit result output
    wire O1;                // Overflow flag
    wire O2, O3, O4, O5;    // Other flags
    reg CLK;                // Clock signal
    reg ASYNCRESET;         // Async reset signal (connected, but not used by DUT logic)

    // Test index tracking
    integer test_index;
    integer test_passed;
    integer test_failed;
    integer i;

    // DUT instantiation - Instantiating the PURELY COMBINATIONAL version
    Combinational_MAC_Pure uut (
        .alu(alu),
        .signed_(signed_), // Still assuming signed operation in DUT
        .a(a),
        .b(b),
        .d(d),             // Connected, but likely unused in pure combinational logic
        .O0(O0),
        .O1(O1),
        .O2(O2),
        .O3(O3),
        .O4(O4),
        .O5(O5),
        .CLK(CLK),         // Connected for interface compatibility
        .ASYNCRESET(ASYNCRESET) // Connected for interface compatibility
    );

    //--------------------------------------------------------------------------
    // Golden Value Definitions - Recalculated for Combinational_MAC_Pure
    //--------------------------------------------------------------------------

    // Adjust NUM_TESTS based on valid tests for the combinational DUT
    localparam NUM_TESTS = 26; // Reduced count as accumulator tests are removed/repurposed
    reg [8*64-1:0] test_names [0:NUM_TESTS-1];  // Test names
    reg [7:0] test_alu [0:NUM_TESTS-1];         // Control word
    reg [15:0] test_a [0:NUM_TESTS-1];          // Input A
    reg [15:0] test_b [0:NUM_TESTS-1];          // Input B
    reg test_d [0:NUM_TESTS-1];                 // Extra control (effect depends on DUT usage)
    reg signed [15:0] test_result [0:NUM_TESTS-1];     // Expected result (RECALCULATED)
    reg test_overflow [0:NUM_TESTS-1];          // Expected overflow flag (RECALCULATED)

    // Initialization function with RECALCULATED expected values
    initial begin
        // Test vectors based on Combinational_MAC_Pure logic
        // Calculations assume standard signed interpretation for sub-operands
        // 4-bit: -8 to 7
        // 8-bit: -128 to 127
        // Intermediate sums are 19-bit signed, final result saturated to 16-bit signed.

        // 1. Mode 00 (4x4 SIMD Sum) Tests
        test_names[0] = "Mode 00 (4x4) - pos x pos"; // a=[2,3,0,0], b=[1,2,0,0] -> 2*1 + 3*2 + 0 + 0 = 8
        test_alu[0] = 8'h00; test_a[0] = 16'h0302; test_b[0] = 16'h0201; test_d[0] = 0;
        test_result[0] = 16'h0008; test_overflow[0] = 0;

        test_names[1] = "Mode 00 (4x4) - neg(a) x pos"; // a=[2,0,-3,0], b=[1,0,2,0] -> 2*1 + 0 + (-3)*2 + 0 = -4
        test_alu[1] = 8'h00; test_a[1] = 16'hFD02; test_b[1] = 16'h0201; test_d[1] = 0;
        test_result[1] = 16'hFFFC; test_overflow[1] = 0;

        test_names[2] = "Mode 00 (4x4) - neg x neg"; // a=[2,0,-3,0], b=[1,0,-2,0] -> 2*1 + 0 + (-3)*(-2) + 0 = 8
        test_alu[2] = 8'h00; test_a[2] = 16'hFD02; test_b[2] = 16'hFE01; test_d[2] = 0;
        test_result[2] = 16'h0009; test_overflow[2] = 0;

        test_names[3] = "Mode 00 (4x4) - max values (0xF=-1)"; // a=[-1,0,-1,0], b=[-1,0,-1,0] -> (-1)*(-1) + 0 + (-1)*(-1) + 0 = 2
        test_alu[3] = 8'h00; test_a[3] = 16'h0F0F; test_b[3] = 16'h0F0F; test_d[3] = 0;
        test_result[3] = 16'h0002; test_overflow[3] = 0;

        // 2. Mode 11 (2x8 SIMD Sum) Tests (Using alu=0x03)
        test_names[4] = "Mode 11 (2x8) - pos x pos"; // a=[0x12,0x00], b=[0x34,0x00] -> (18*52) + (0*0) = 936
        test_alu[4] = 8'h03; test_a[4] = 16'h0012; test_b[4] = 16'h0034; test_d[4] = 0;
        test_result[4] = 16'h03A8; test_overflow[4] = 0;

        test_names[5] = "Mode 11 (2x8) - neg(a) x pos"; // a=[0x12,0xFF], b=[0x34,0x00] -> (18*52) + (-1*0) = 936
        test_alu[5] = 8'h03; test_a[5] = 16'hFF12; test_b[5] = 16'h0034; test_d[5] = 0;
        test_result[5] = 16'h03A8; test_overflow[5] = 0;

        test_names[6] = "Mode 11 (2x8) - neg x neg"; // a=[0x12,0xFF], b=[0x34,0xFF] -> (18*52) + (-1*-1) = 936 + 1 = 937
        test_alu[6] = 8'h03; test_a[6] = 16'hFF12; test_b[6] = 16'hFF34; test_d[6] = 0;
        test_result[6] = 16'h03A9; test_overflow[6] = 0;

        test_names[7] = "Mode 11 (2x8) - max values"; // a=[0x7F,0x7F], b=[0x7F,0x7F] -> (127*127) + (127*127) = 16129 + 16129 = 32258
        test_alu[7] = 8'h03; test_a[7] = 16'h7F7F; test_b[7] = 16'h7F7F; test_d[7] = 0;
        test_result[7] = 16'h7E02; test_overflow[7] = 0;

        // 3. Mode 10 (Low 2x4 + High 8x8) Tests (Using alu=0x02)
        test_names[8] = "Mode 10 (L2x4+H8) - pos demo"; // a=[4,3,2,1], b=[-8,7,6,5]; a_h=0x12, b_h=0x56 -> (4*-8) + (3*7) + (18*86) = -32 + 21 + 1548 = 1537
        test_alu[8] = 8'h02; test_a[8] = 16'h1234; test_b[8] = 16'h5678; test_d[8] = 0;
        test_result[8] = 16'h0601; test_overflow[8] = 0;

        // 4. Mode 01 (Low 8x8 + High 2x4) Tests (Using alu=0x01)
        test_names[9] = "Mode 01 (L8+H2x4) - mixed sign demo"; // a_l=0x34, b_l=0x78; a=[4,3,2,-1], b=[-8,7,6,5] -> (52*120) + (2*6) + (-1*5) = 6240 + 12 - 5 = 6247
        test_alu[9] = 8'h01; test_a[9] = 16'hF234; test_b[9] = 16'h5678; test_d[9] = 0;
        test_result[9] = 16'h1867; test_overflow[9] = 0;

        // 5. Add-only mode tests (alu[5]=1)
        test_names[10] = "Add-only mode - pos + pos"; // 16 + 32 = 48
        test_alu[10] = 8'h20; test_a[10] = 16'h0010; test_b[10] = 16'h0020; test_d[10] = 0;
        test_result[10] = 16'h0030; test_overflow[10] = 0;

        test_names[11] = "Add-only mode - pos + neg"; // 16 + (-32) = -16
        test_alu[11] = 8'h20; test_a[11] = 16'h0010; test_b[11] = 16'hFFE0; test_d[11] = 0;
        test_result[11] = 16'hFFF0; test_overflow[11] = 0;

        test_names[12] = "Add-only mode - neg + neg"; // -16 + (-32) = -48
        test_alu[12] = 8'h20; test_a[12] = 16'hFFF0; test_b[12] = 16'hFFE0; test_d[12] = 0;
        test_result[12] = 16'hFFD0; test_overflow[12] = 0;

        // 6. Overflow tests (using AddOnly for clear examples)
        test_names[13] = "Overflow test - AddOnly positive"; // 0x7FFF + 1 = 32767 + 1 = 32768 -> Overflow, Saturate to 0x7FFF
        test_alu[13] = 8'h20; test_a[13] = 16'h7FFF; test_b[13] = 16'h0001; test_d[13] = 0;
        test_result[13] = 16'h7FFF; test_overflow[13] = 1;

        test_names[14] = "Overflow test - AddOnly negative"; // 0x8000 + (-1) = -32768 - 1 = -32769 -> Overflow, Saturate to 0x8000
        test_alu[14] = 8'h20; test_a[14] = 16'h8000; test_b[14] = 16'hFFFF; test_d[14] = 0;
        test_result[14] = 16'h8000; test_overflow[14] = 1;

        // 7. Repurposed tests: More mode examples
        test_names[15] = "Mode 01 (L8+H2x4) example 2"; // a=[0x22,0x11], b=[0x44,0x33] -> (34*68) + (1*3) + (1*3) = 2312 + 3 + 3 = 2318
        test_alu[15] = 8'h01; test_a[15] = 16'h1122; test_b[15] = 16'h3344; test_d[15] = 0;
        test_result[15] = 16'h090E; test_overflow[15] = 0;

        test_names[16] = "Mode 10 (L2x4+H8) example 2"; // a=[2,2,1,1], b=[4,4,3,3]; a_h=0x11, b_h=0x33 -> (2*4) + (2*4) + (17*51) = 8 + 8 + 867 = 883
        test_alu[16] = 8'h02; test_a[16] = 16'h1122; test_b[16] = 16'h3344; test_d[16] = 0;
        test_result[16] = 16'h0373; test_overflow[16] = 0;

        // Test 17-19: Can add more specific mode boundary cases, saturation cases for mult modes etc.
        test_names[17] = "Mode 00 (4x4) - Near positive overflow"; // a=[7,7,7,7], b=[7,7,7,7] -> 4 * (7*7) = 4*49 = 196
        test_alu[17] = 8'h00; test_a[17] = 16'h7777; test_b[17] = 16'h7777; test_d[17] = 0;
        test_result[17] = 16'h00C4; test_overflow[17] = 0;

        test_names[18] = "Mode 11 (2x8) - Large sum, no overflow"; // a=[96,96], b=[96,96] -> (96*96) + (96*96) = 9216 + 9216 = 18432
        test_alu[18] = 8'h03; test_a[18] = 16'h6060; test_b[18] = 16'h6060; test_d[18] = 0;
        test_result[18] = 16'h4800; test_overflow[18] = 0;

        // Test 19: Example causing multiplication overflow (if intermediate sum exceeds 19 bits - unlikely here)
        // Or a specific saturation case for multiplication result
        test_names[19] = "Mode 11 (2x8) - Neg values"; // a=[-1,-1], b=[-1,-2] -> (-1*-1) + (-1*-2) = 1 + 2 = 3
        test_alu[19] = 8'h03; test_a[19] = 16'hFFFF; test_b[19] = 16'hFEFF; test_d[19] = 0;
        test_result[19] = 16'h0003; test_overflow[19] = 0;


        // 8. Various boundary condition tests
        test_names[20] = "Boundary condition - zero times zero (Mode 00)";
        test_alu[20] = 8'h00; test_a[20] = 16'h0000; test_b[20] = 16'h0000; test_d[20] = 0;
        test_result[20] = 16'h0000; test_overflow[20] = 0;

        test_names[21] = "Boundary condition - max pos * 1 (Mode 11)"; // a=[0, 127], b=[0, 1] -> 0 + 127*1 = 127
        test_alu[21] = 8'h03; test_a[21] = 16'h7F00; test_b[21] = 16'h0100; test_d[21] = 0;
        test_result[21] = 16'h007F; test_overflow[21] = 0;

        test_names[22] = "Boundary condition - min neg * 1 (Mode 11)"; // a=[0, -128], b=[0, 1] -> 0 + (-128)*1 = -128
        test_alu[22] = 8'h03; test_a[22] = 16'h8000; test_b[22] = 16'h0100; test_d[22] = 0;
        test_result[22] = 16'hFF80; test_overflow[22] = 0;

        // 9. Sign bit tests
        test_names[23] = "Sign bit test - 0x8000 (Mode 00)"; // a=[0,0,0,-8], b=[1,0,0,0] -> 0*1 + 0 + 0 + (-8)*0 = 0
        test_alu[23] = 8'h00; test_a[23] = 16'h8000; test_b[23] = 16'h0001; test_d[23] = 0;
        test_result[23] = 16'h0000; test_overflow[23] = 0;

        // 10. Multi sub-operand combination tests
        test_names[24] = "Multi sub-operand - Mode 00 full"; // a=[4,3,2,1], b=[-8,7,6,5] -> (4*-8)+(3*7)+(2*6)+(1*5) = -32+21+12+5 = 6
        test_alu[24] = 8'h00; test_a[24] = 16'h1234; test_b[24] = 16'h5678; test_d[24] = 0;
        test_result[24] = 16'h0006; test_overflow[24] = 0;

        test_names[25] = "Multi sub-operand - Mode 11 full"; // a=[0x34,0x12], b=[0x78,0x56] -> (52*120) + (18*86) = 6240 + 1548 = 7788
        test_alu[25] = 8'h03; test_a[25] = 16'h1234; test_b[25] = 16'h5678; test_d[25] = 0;
        test_result[25] = 16'h1E6C; test_overflow[25] = 0;

        // Tests 26-29 are removed as they were accumulator-specific.
    end

    //--------------------------------------------------------------------------
    // Test Execution Task
    //--------------------------------------------------------------------------
    task execute_test;
        input integer vec_idx;
        begin
            test_index = vec_idx;

            @(posedge CLK);
            // Set inputs
            alu = test_alu[vec_idx];
            a = test_a[vec_idx];
            b = test_b[vec_idx];
            d = test_d[vec_idx];
            signed_ = 1'b1;  // Fixed as signed for now

            // Wait for combinational logic to settle (checked after next edge)
            @(posedge CLK);
            #5; // Small delay after clock edge allows signals to propagate for waveform viewing/checking

            // Print test information
            $display("========================================");
            $display("Test %0d: %s", vec_idx, test_names[vec_idx]);
            $display("Inputs: a=0x%h (%0d), b=0x%h (%0d), alu=0x%h, d=%b",
                     a, $signed(a), b, $signed(b), alu, d);

            // Display Mode based on O4 (mode[1]) and O3 (mode[0]) outputs
            $display("Mode: %s, Add Only: %b",
                     (O4 == 0 && O3 == 0) ? "4x4 SIMD" :
                     (O4 == 0 && O3 == 1) ? "L8+H2x4 Mixed" :
                     (O4 == 1 && O3 == 0) ? "L2x4+H8 Mixed" :
                     (O4 == 1 && O3 == 1) ? "2x8 SIMD" : "Unknown",
                     O5); // O5 directly reflects is_add_only

            // Validate results
            if (O0 !== test_result[vec_idx] ||
                O1 !== test_overflow[vec_idx]) begin
                $display("Test FAILED!");
                $display("Actual result: O0=0x%h (%0d), Overflow: O1=%b",
                         O0, $signed(O0), O1);
                $display("Expected result: 0x%h (%0d), Expected overflow: %b",
                         test_result[vec_idx],
                         $signed(test_result[vec_idx]),
                         test_overflow[vec_idx]);
                test_failed = test_failed + 1;
            end else begin
                $display("Test PASSED! Result: O0=0x%h (%0d), Overflow: O1=%b",
                         O0, $signed(O0), O1);
                test_passed = test_passed + 1;
            end
            $display("========================================\n");
        end
    endtask

    // Generate clock signal
    initial begin
        CLK = 0;
        forever #5 CLK = ~CLK;  // 10ns period (100MHz)
    end

    // Test sequence
    initial begin
        // Initialize signals
        ASYNCRESET = 1; // Assert reset
        alu = 8'h00;
        a = 16'h0000;
        b = 16'h0000;
        d = 0;
        signed_ = 1'b1;
        test_passed = 0;
        test_failed = 0;

        #20; // Hold reset for a bit
        ASYNCRESET = 0; // Deassert reset
        #20; // Wait for stability after reset

        // Execute all defined test vectors
        for (i = 0; i < NUM_TESTS; i = i + 1) begin
            execute_test(i);
        end

        // Print final statistics
        $display("Tests completed!");
        $display("Passed: %0d", test_passed);
        $display("Failed: %0d", test_failed);
        $display("Total: %0d", NUM_TESTS);

        // End simulation
        #100;
        $finish;
    end

    // Simulation waveform output (optional, uncomment if needed)
    initial begin
        $dumpfile("Combinational_MAC_Pure_tb.vcd");
        $dumpvars(0, Combinational_MAC_Pure_tb);
    end

endmodule