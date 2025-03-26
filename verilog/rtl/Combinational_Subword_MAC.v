//------------------------------------------------------------------------------
// Corrected Purely Combinational MAC (No Internal State) - Radix-4 Booth
//------------------------------------------------------------------------------
module Combinational_MAC_Pure (
    input [7:0] alu,          // Opcode: [5]:add_only, [1:0]:mode
    input signed_,            // Signed/unsigned flag (Currently ignored, assumed signed)
    input signed [15:0] a,    // Input data
    input signed [15:0] b,    // Weight data
    input d,                  // Extra control (Can be repurposed)
    output [15:0] O0,         // 16-bit result output (Saturated)
    output O1,                // Overflow flag
    output O2,                // Conditional module output (e.g., result[8])
    output O3,                // Output MAC mode[0]
    output O4,                // Output MAC mode[1]
    output O5,                // Output add_only mode flag
    input CLK,                // Interface compatibility, unused internally
    input ASYNCRESET          // Interface compatibility, unused internally
);

    // 1. Control Signal Decoding (Combinational)
    wire [1:0] mode = alu[1:0];
    wire is_add_only = alu[5];

    // 2. Operand Extraction (Combinational)
    wire signed [3:0] a_op4 [3:0]; wire signed [3:0] b_op4 [3:0];
    wire signed [7:0] a_op8 [1:0]; wire signed [7:0] b_op8 [1:0];

    assign a_op4[0]=a[3:0]; assign a_op4[1]=a[7:4]; assign a_op4[2]=a[11:8]; assign a_op4[3]=a[15:12];
    assign b_op4[0]=b[3:0]; assign b_op4[1]=b[7:4]; assign b_op4[2]=b[11:8]; assign b_op4[3]=b[15:12];
    assign a_op8[0]=a[7:0]; assign a_op8[1]=a[15:8];
    assign b_op8[0]=b[7:0]; assign b_op8[1]=b[15:8];

    // 3. Multiplier Instantiation (Combinational) - USING CORRECTED MULTIPLIERS
    wire signed [7:0] mult4_results [3:0];  // 4x4 results
    wire signed [15:0] mult8_results [1:0]; // 8x8 results

    // Instantiate 4 corrected 4x4 multipliers
    booth_4x4_radix4 mult4_0 (.a(a_op4[0]), .b(b_op4[0]), .product(mult4_results[0]));
    booth_4x4_radix4 mult4_1 (.a(a_op4[1]), .b(b_op4[1]), .product(mult4_results[1]));
    booth_4x4_radix4 mult4_2 (.a(a_op4[2]), .b(b_op4[2]), .product(mult4_results[2]));
    booth_4x4_radix4 mult4_3 (.a(a_op4[3]), .b(b_op4[3]), .product(mult4_results[3]));

    // Instantiate 2 corrected 8x8 multipliers
    booth_8x8_radix4 mult8_0 (.a(a_op8[0]), .b(b_op8[0]), .product(mult8_results[0]));
    booth_8x8_radix4 mult8_1 (.a(a_op8[1]), .b(b_op8[1]), .product(mult8_results[1]));

    // 4. Summation Logic (Combinational)
    wire signed [18:0] sum_mode00, sum_mode01, sum_mode10, sum_mode11, sum_add_only;

    assign sum_mode00   = {{11{mult4_results[0][7]}}, mult4_results[0]} + {{11{mult4_results[1][7]}}, mult4_results[1]} + {{11{mult4_results[2][7]}}, mult4_results[2]} + {{11{mult4_results[3][7]}}, mult4_results[3]};
    assign sum_mode01   = {{3{mult8_results[0][15]}}, mult8_results[0]} + {{11{mult4_results[2][7]}}, mult4_results[2]} + {{11{mult4_results[3][7]}}, mult4_results[3]};
    assign sum_mode10   = {{11{mult4_results[0][7]}}, mult4_results[0]} + {{11{mult4_results[1][7]}}, mult4_results[1]} + {{3{mult8_results[1][15]}}, mult8_results[1]};
    assign sum_mode11   = {{3{mult8_results[0][15]}}, mult8_results[0]} + {{3{mult8_results[1][15]}}, mult8_results[1]};
    assign sum_add_only = {{3{a[15]}}, a} + {{3{b[15]}}, b};

    wire signed [18:0] current_sum_comb = is_add_only ? sum_add_only :
                                         (mode == 2'b00) ? sum_mode00 :
                                         (mode == 2'b01) ? sum_mode01 :
                                         (mode == 2'b10) ? sum_mode10 :
                                         /*(mode == 2'b11)*/ sum_mode11; // Default case for mode 11

    // 5. Overflow Detection & CORRECTED Saturation (Combinational)
    wire overflow_comb;
    wire signed [15:0] result_comb;

    assign overflow_comb = (current_sum_comb[18:16] != {3{current_sum_comb[15]}});

    // CORRECTED Saturation Logic
    assign result_comb = overflow_comb ?
                         (current_sum_comb[18] ? 16'sh8000 : 16'sh7FFF) : // Neg overflow -> 8000, Pos overflow -> 7FFF
                         current_sum_comb[15:0];

    // 6. Output Assignment (Combinational)
    assign O0 = result_comb;
    assign O1 = overflow_comb;
    assign O2 = result_comb[8];
    assign O3 = mode[0];
    assign O4 = mode[1];
    assign O5 = is_add_only;

endmodule

//------------------------------------------------------------------------------
// Helper Module: Radix-4 Booth Encoder (Common for 4x4 and 8x8)
// Takes 3 bits of multiplier (b_i+1, b_i, b_i-1)
// Outputs control signals for PP generator: sel_1x, sel_2x, negate_pp
//------------------------------------------------------------------------------
module booth_radix4_encoder (
    input wire [2:0] b_group,   // Input group (b_i+1, b_i, b_i-1)
    output wire sel_1x,      // Select A for partial product
    output wire sel_2x,      // Select 2A for partial product
    output wire negate_pp    // Negate the selected partial product
);
    // Radix-4 Booth Encoding Logic
    // Operation | Value | b_group | sel_1x | sel_2x | negate_pp
    // ----------|-------|---------|--------|--------|-----------
    // +0        | 0     | 000     | 0      | 0      | 0
    // +A        | +1    | 001     | 1      | 0      | 0
    // +A        | +1    | 010     | 1      | 0      | 0
    // +2A       | +2    | 011     | 0      | 1      | 0
    // -2A       | -2    | 100     | 0      | 1      | 1
    // -A        | -1    | 101     | 1      | 0      | 1
    // -A        | -1    | 110     | 1      | 0      | 1
    // -0 (-0)   | 0     | 111     | 0      | 0      | 0 // Treat as 0

    assign sel_1x    = (b_group == 3'b001) || (b_group == 3'b010) || (b_group == 3'b101) || (b_group == 3'b110);
    assign sel_2x    = (b_group == 3'b011) || (b_group == 3'b100);
    assign negate_pp = b_group[2]; // Negate if the most significant bit of the group is 1

endmodule

//------------------------------------------------------------------------------
// Helper Module: Radix-4 Partial Product Generator
// Generates PP based on multiplicand (a), 2*a, and encoder outputs
// WIDTH_A is the original width of 'a' (e.g., 4 or 8)
// WIDTH_PP is the width of the partial product (e.g., 6 for 4x4, 10 for 8x8)
//------------------------------------------------------------------------------
module booth_radix4_pp_gen #(
    parameter WIDTH_A = 8,             // Width of multiplicand 'a'
    parameter WIDTH_PP = WIDTH_A + 2   // Width of the generated partial product
)(
    input wire signed [WIDTH_A:0] a_ext, // Sign-extended multiplicand 'a' (Width A+1)
    input wire sel_1x,
    input wire sel_2x,
    input wire negate_pp,
    output wire signed [WIDTH_PP-1:0] pp // Generated Partial Product
);
    wire signed [WIDTH_A+1:0] a_x2; // Width A+2 needed for a_ext << 1
    wire signed [WIDTH_PP-1:0] term_sel;
    wire signed [WIDTH_PP-1:0] term_neg;

    assign a_x2 = a_ext << 1; // Calculate 2*a (signed shift)

    // Select term based on sel_1x, sel_2x (sign-extend to PP width)
    // Note: Sign extension needed carefully
    assign term_sel = sel_1x ? {{WIDTH_PP - (WIDTH_A+1){a_ext[WIDTH_A]}}, a_ext} : // Select A (sign extended)
                      sel_2x ? {{WIDTH_PP - (WIDTH_A+2){a_x2[WIDTH_A+1]}}, a_x2} : // Select 2A (sign extended)
                               {WIDTH_PP{1'b0}};                                   // Select 0

    // Negate if required (Two's complement)
    assign term_neg = (~term_sel) + 1'b1;

    // Final Partial Product
    assign pp = negate_pp ? term_neg : term_sel;

endmodule


//------------------------------------------------------------------------------
// CORRECTED 4x4 Signed Multiplier using Radix-4 Booth
//------------------------------------------------------------------------------
module booth_4x4_radix4 (
    input signed [3:0] a,
    input signed [3:0] b,
    output signed [7:0] product
);
    localparam N = 4;
    localparam PP_WIDTH = N + 2; // 6 bits for PP
    localparam SUM_WIDTH = 2*N; // 8 bits for final product

    wire [2:0] b_groups [N/2-1:0];      // 2 groups for 4-bit b
    wire sel_1x [N/2-1:0], sel_2x [N/2-1:0], negate_pp [N/2-1:0]; // Encoder outputs
    wire signed [N:0] a_ext = {a[N-1], a}; // 5 bits
    wire signed [PP_WIDTH-1:0] pp [N/2-1:0]; // Partial products (6 bits each)
    wire signed [SUM_WIDTH-1:0] shifted_pp [N/2-1:0]; // Shifted & extended PPs (8 bits)

    // 1. Form Booth groups (append b[-1]=0 for first group)
    assign b_groups[0] = {b[1], b[0], 1'b0};
    assign b_groups[1] = {b[3], b[2], b[1]};

    // 2. Encode each group
    genvar i;
    generate
        for (i = 0; i < N/2; i = i + 1) begin : enc_gen
            booth_radix4_encoder encoder (
                .b_group(b_groups[i]),
                .sel_1x(sel_1x[i]),
                .sel_2x(sel_2x[i]),
                .negate_pp(negate_pp[i])
            );
        end
    endgenerate

    // 3. Generate Partial Products
    generate
        for (i = 0; i < N/2; i = i + 1) begin : pp_gen
            booth_radix4_pp_gen #(
                .WIDTH_A(N),         // Original 'a' width = 4
                .WIDTH_PP(PP_WIDTH)  // PP width = 6
            ) pp_inst (
                .a_ext(a_ext),
                .sel_1x(sel_1x[i]),
                .sel_2x(sel_2x[i]),
                .negate_pp(negate_pp[i]),
                .pp(pp[i])
            );
        end
    endgenerate

    // 4. Shift and Sign Extend Partial Products to SUM_WIDTH (8 bits)
    // pp[0] shifted by 2*0 = 0
    assign shifted_pp[0] = {{SUM_WIDTH - PP_WIDTH{pp[0][PP_WIDTH-1]}}, pp[0]};
    // pp[1] shifted by 2*1 = 2
    assign shifted_pp[1] = {{SUM_WIDTH - PP_WIDTH - 2{pp[1][PP_WIDTH-1]}}, pp[1], 2'b00};

    // 5. Final Addition
    assign product = shifted_pp[0] + shifted_pp[1];

endmodule

//------------------------------------------------------------------------------
// CORRECTED 8x8 Signed Multiplier using Radix-4 Booth and Wallace Tree
//------------------------------------------------------------------------------
module booth_8x8_radix4 (
    input signed [7:0] a,
    input signed [7:0] b,
    output signed [15:0] product
);
    localparam N = 8;
    localparam NUM_PP = N/2;        // 4 partial products for Radix-4
    localparam PP_WIDTH = N + 2;    // 10 bits for PP
    localparam TREE_WIDTH = 2*N + 1; // 17 bits for Wallace tree width safety
    localparam SUM_WIDTH = 2*N;     // 16 bits for final product

    wire [2:0] b_groups [NUM_PP-1:0];      // 4 groups for 8-bit b
    wire sel_1x [NUM_PP-1:0], sel_2x [NUM_PP-1:0], negate_pp [NUM_PP-1:0]; // Encoder outputs
    wire signed [N:0] a_ext = {a[N-1], a}; // 9 bits
    wire signed [PP_WIDTH-1:0] pp [NUM_PP-1:0]; // Partial products (10 bits each)
    wire signed [TREE_WIDTH-1:0] shifted_pp [NUM_PP-1:0]; // Shifted & extended PPs (17 bits)

    // 1. Form Booth groups
    assign b_groups[0] = {b[1], b[0], 1'b0};
    assign b_groups[1] = {b[3], b[2], b[1]};
    assign b_groups[2] = {b[5], b[4], b[3]};
    assign b_groups[3] = {b[7], b[6], b[5]};

    // 2. Encode each group
    genvar i;
    generate
        for (i = 0; i < NUM_PP; i = i + 1) begin : enc_gen_8x8
            booth_radix4_encoder encoder (
                .b_group(b_groups[i]),
                .sel_1x(sel_1x[i]),
                .sel_2x(sel_2x[i]),
                .negate_pp(negate_pp[i])
            );
        end
    endgenerate

    // 3. Generate Partial Products
    generate
        for (i = 0; i < NUM_PP; i = i + 1) begin : pp_gen_8x8
            booth_radix4_pp_gen #(
                .WIDTH_A(N),         // Original 'a' width = 8
                .WIDTH_PP(PP_WIDTH)  // PP width = 10
            ) pp_inst (
                .a_ext(a_ext),
                .sel_1x(sel_1x[i]),
                .sel_2x(sel_2x[i]),
                .negate_pp(negate_pp[i]),
                .pp(pp[i])
            );
        end
    endgenerate

    // 4. Shift and Sign Extend Partial Products to TREE_WIDTH (17 bits)
    // pp[i] needs to be shifted left by 2*i bits
    assign shifted_pp[0] = {{TREE_WIDTH - PP_WIDTH {pp[0][PP_WIDTH-1]}}, pp[0]};           // Shift 0
    assign shifted_pp[1] = {{TREE_WIDTH - PP_WIDTH - 2{pp[1][PP_WIDTH-1]}}, pp[1], 2'b00}; // Shift 2
    assign shifted_pp[2] = {{TREE_WIDTH - PP_WIDTH - 4{pp[2][PP_WIDTH-1]}}, pp[2], 4'b00}; // Shift 4
    assign shifted_pp[3] = {{TREE_WIDTH - PP_WIDTH - 6{pp[3][PP_WIDTH-1]}}, pp[3], 6'b00}; // Shift 6


    // 5. Wallace Tree Compression (4 PPs -> 2 vectors) using 17-bit CSAs
    wire signed [TREE_WIDTH-1:0] sum1, carry1;
    wire signed [TREE_WIDTH-1:0] sum2, carry2;

    // Stage 1: Compress pp0, pp1, pp2
    wallace_csa #(TREE_WIDTH) csa1 (
        .a(shifted_pp[0]),
        .b(shifted_pp[1]),
        .c(shifted_pp[2]),
        .sum(sum1),
        .carry(carry1) // carry1[i] is carry out of bit i
    );

    // Stage 2: Compress sum1, (carry1 << 1), pp3
    wallace_csa #(TREE_WIDTH) csa2 (
        .a(sum1),
        .b({carry1[TREE_WIDTH-2:0], 1'b0}), // Shift carry1 left by 1
        .c(shifted_pp[3]),
        .sum(sum2),
        .carry(carry2) // carry2[i] is carry out of bit i
    );

    // 6. Final Addition (Carry Propagate Adder)
    wire signed [TREE_WIDTH:0] final_sum_internal; // Use 18 bits for safety (17+17)
    assign final_sum_internal = sum2 + {carry2[TREE_WIDTH-2:0], 1'b0}; // Add sum2 and shifted carry2

    // Assign final 16-bit product
    assign product = final_sum_internal[SUM_WIDTH-1:0]; // Take lower 16 bits

endmodule


//------------------------------------------------------------------------------
// Parameterized Wallace Carry Save Adder (CSA) - Unchanged
//------------------------------------------------------------------------------
module wallace_csa #(
    parameter WIDTH = 17 // Default width matching TREE_WIDTH
)(
    input [WIDTH-1:0] a,
    input [WIDTH-1:0] b,
    input [WIDTH-1:0] c,
    output [WIDTH-1:0] sum,
    output [WIDTH-1:0] carry
);
    assign sum = a ^ b ^ c;
    assign carry = (a & b) | (b & c) | (a & c);
endmodule