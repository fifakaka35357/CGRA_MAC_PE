// 纯组合逻辑接口
module Combinational_MAC (
    input [7:0] alu,          // 操作码
    input signed_,            // 有符号/无符号标志 (现在忽略，固定为有符号)
    input [15:0] a,           // 输入数据
    input [15:0] b,           // 权重数据
    input d,                  // 可用作额外控制
    output [15:0] O0,         // 16位结果输出
    output O1,                // 溢出标志
    output O2,                // 用于条件模块
    output O3,                // 输出MAC模式[0]
    output O4,                // 输出MAC模式[1]
    output O5,                // 输出MAC模式信息
    input CLK,                // 添加时钟信号（虽然是组合逻辑但保持接口一致）
    input ASYNCRESET          // 添加异步复位信号（虽然是组合逻辑但保持接口一致）
);
    wire [1:0] mode;         // 模式编码: 00:4x4bit, 01:2x8bit, 10:混合模式, 11:预留给未来扩展
    wire clear_acc;
    reg add_only;           // 仅累加模式（跳过乘法）
    reg use_acc;            // 是否使用累积值
    wire [15:0] data_in;
    wire [15:0] weight;
    
    assign clear_acc = alu[3] | d;            // 清零信号
    assign mode = alu[1:0];
    assign data_in = a;
    assign weight = b;
    
    // 实例化纯组合逻辑MAC模块
    wire overflow;                            // 溢出指示，用于调试
    wire [15:0] result;                       // 16位计算结果
    reg [15:0] prev_accum;                    // 外部累加值（当启用乘加累积功能时使用）
    // 输出赋值 - 保持与原始接口兼容
    assign O0 = result;              // 结果输出 (已经饱和处理)
    assign O1 = overflow;            // 溢出标志
    assign O2 = result[8];           // 用于条件模块的位
    assign O3 = mode[0];             // 模式位[0]
    assign O4 = mode[1];             // 模式位[1]
    assign O5 = add_only;            // 输出add_only模式标志
    //--------------------------------------------------------------------------
    // 内部信号定义
    //--------------------------------------------------------------------------
    // wire [3:0] en_slice;             // 使能信号
    
    // 有符号操作数
    reg signed [7:0] a_operands [3:0];  // 操作数A (数据)
    reg signed [7:0] b_operands [3:0];  // 操作数B (权重)
    
    // 乘法结果
    wire signed [15:0] mult_results [3:0];

    //--------------------------------------------------------------------------
    // 2. 数据准备 - 根据模式提取和扩展操作数
    //--------------------------------------------------------------------------
    always @(posedge CLK) begin // negedge
        if (clear_acc)
            prev_accum <= 0;
        else
            prev_accum <= result;
        add_only <= alu[5];                 // 使用独立的控制位 alu[5] 控制仅累加模式
        use_acc <= alu[2];                  // 单独使用 alu[2] 控制是否使用累积值
        if (mode[0]) 
            begin
                a_operands[0] <= {{4{data_in[3]}}, data_in[3:0]};    // 符号扩展
                a_operands[1] <= {{4{data_in[7]}}, data_in[7:4]};
                b_operands[0] <= {{4{weight[3]}}, weight[3:0]};
                b_operands[1] <= {{4{weight[7]}}, weight[7:4]};
                // en_slice[1:0] <= 'b11;
            end
        else 
            begin
                a_operands[0] <= data_in[7:0];
                a_operands[1] <= 'sh00;
                b_operands[0] <= weight[7:0];
                b_operands[1] <= 'sh00;
                // en_slice[1:0] <= 'b01;
            end
        
        if (mode[1]) 
            begin
                a_operands[2] <= {{4{data_in[11]}}, data_in[11:8]};
                a_operands[3] <= {{4{data_in[15]}}, data_in[15:12]};
                b_operands[2] <= {{4{weight[11]}}, weight[11:8]};
                b_operands[3] <= {{4{weight[15]}}, weight[15:12]};
                // en_slice[3:2] <= 'b11;
            end
        else 
            begin
                a_operands[2] <= data_in[15:8];
                a_operands[3] <= 'sh00;
                b_operands[2] <= weight[15:8];
                b_operands[3] <= 'sh00;
                // en_slice[3:2] <= 'b01;
            end
    end
    
    //--------------------------------------------------------------------------
    // 3. 乘法单元阵列 - 实例化4个乘法器 (保持不变，本身就是组合逻辑)
    //--------------------------------------------------------------------------
    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin: mult_units
            booth_8x8 booth_mult_inst (
                .a(a_operands[i]),
                .b(b_operands[i]),
                .product(mult_results[i])
            );
        end
    endgenerate
    
    //--------------------------------------------------------------------------
    // 4. 累加树 - 分层设计以降低关键路径延迟，并支持仅累加模式
    //--------------------------------------------------------------------------
    // 第一级累加 - 将4个输入分成两组累加
    reg signed [16:0] sum_stage1_a, sum_stage1_b; // 第一级累加
    always @(*) begin // posedge CLK
        if (~add_only)
            begin
                sum_stage1_a <= mult_results[0] + mult_results[1];
                sum_stage1_b <= mult_results[2] + mult_results[3];
            end
        else
            begin
                sum_stage1_a <= {data_in[15], data_in[15:0]};
                sum_stage1_b <= {weight[15], weight[15:0]};
            end
    end
    // 第二级累加
    reg signed [18:0] current_sum;                 // 最终结果
    always @(*) begin
        current_sum <= sum_stage1_a + sum_stage1_b + (use_acc ? {{2{prev_accum[15]}}, prev_accum} : 'sh0);
    end
    //--------------------------------------------------------------------------
    // 5. 溢出检测与饱和处理 (保持不变，本身就是组合逻辑)
    //--------------------------------------------------------------------------
    // 检测溢出 - 当符号位与最高有效位不一致时发生溢出
    assign overflow = (current_sum[18:16] != {3{current_sum[15]}});
    
    // 饱和处理 - 溢出时截断到16位范围
    assign result = overflow ? 
                    (current_sum[18] ? 16'sh7FFF : 16'sh8000) : // 负/正溢出
                    current_sum[15:0];                          // 无溢出
endmodule

// 其他子模块保持不变...
// booth_8x8, booth_pp_gen, wallace_csa
//------------------------------------------------------------------------------
// 8x8 有符号乘法器 - 使用Modified Booth算法(Radix-2)与Wallace树
//------------------------------------------------------------------------------
module booth_8x8 (
    input signed [7:0] a,        // 8位有符号被乘数
    input signed [7:0] b,        // 8位有符号乘数
    output signed [15:0] product // 乘积结果
);
    // Radix-2 Booth编码与部分积
    wire [1:0] booth_enc [3:0];
    wire [8:0] pp [3:0];         // 部分积
    wire [16:0] shifted_pp [3:0]; // 移位后的部分积
    
    // 扩展操作数用于Booth编码
    wire [8:0] a_ext = {a[7], a};     // 符号扩展一位
    wire [8:0] b_ext = {b, 1'b0};     // 添加一个0位
    
    // Radix-2 Booth编码
    assign booth_enc[0] = b_ext[1:0];
    assign booth_enc[1] = b_ext[3:2];
    assign booth_enc[2] = b_ext[5:4];
    assign booth_enc[3] = b_ext[7:6];
    
    // 使用参数化的Booth部分积生成器
    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin: pp_gen
            booth_pp_gen #(
                .WIDTH(9)
            ) booth_pp_inst (
                .a(a_ext),
                .enc(booth_enc[i]),
                .pp(pp[i])
            );
        end
    endgenerate
    
    // 移位部分积
    assign shifted_pp[0] = {8'b0, pp[0]};
    assign shifted_pp[1] = {6'b0, pp[1], 2'b00};
    assign shifted_pp[2] = {4'b0, pp[2], 4'b0000};
    assign shifted_pp[3] = {2'b0, pp[3], 6'b000000};
    
    // Wallace树压缩
    wire [16:0] sum1, carry1;
    wire [16:0] sum2, carry2;
    wire [16:0] sum3, carry3;
    
    // 第一级压缩: (pp0, pp1, pp2) -> (sum1, carry1)
    wallace_csa #(17) csa1 (
        .a(shifted_pp[0]),
        .b(shifted_pp[1]),
        .c(shifted_pp[2]),
        .sum(sum1),
        .carry(carry1)
    );
    
    // 第二级压缩: (sum1, carry1, pp3) -> (sum2, carry2)
    wallace_csa #(17) csa2 (
        .a(sum1),
        .b({carry1[15:0], 1'b0}), // 进位左移一位
        .c(shifted_pp[3]),
        .sum(sum2),
        .carry(carry2)
    );
    
    // 最终加法
    assign product = sum2[15:0] + {carry2[14:0], 1'b0};
    
endmodule

//------------------------------------------------------------------------------
// 参数化Booth部分积生成器
//------------------------------------------------------------------------------
module booth_pp_gen #(
    parameter WIDTH = 9
)(
    input wire [WIDTH-1:0] a,      // 扩展的被乘数
    input wire [1:0] enc,          // Radix-2 Booth编码
    output reg [WIDTH-1:0] pp     // 部分积
);
    // Modified Booth (Radix-2)编码逻辑
    always @(*) begin
        case (enc)
            2'b01: pp <= a;                             // +A
            2'b10: pp <= (~a) + {{(WIDTH-1){1'b0}}, 1'b1}; // -A
            default: pp <= {WIDTH{1'b0}};              // +0
        endcase
    end
endmodule

//------------------------------------------------------------------------------
// 参数化Wallace进位保存加法器 (CSA)
//------------------------------------------------------------------------------
module wallace_csa #(
    parameter WIDTH = 16
)(
    input [WIDTH-1:0] a,
    input [WIDTH-1:0] b,
    input [WIDTH-1:0] c,
    output [WIDTH-1:0] sum,
    output [WIDTH-1:0] carry
);
    // 3:2压缩器 - 将3个输入压缩为2个输出
    genvar i;
    generate
        for (i = 0; i < WIDTH; i = i + 1) begin: gen_csa
            // 计算每位的和与进位
            assign sum[i] = a[i] ^ b[i] ^ c[i];
            assign carry[i] = (a[i] & b[i]) | (b[i] & c[i]) | (a[i] & c[i]);
        end
    endgenerate
endmodule
