module Combinational_Subword_MAC (
    // 纯组合逻辑接口
    input wire [1:0] mode,           // 00:4x4bit, 01:2x8bit, 10:混合模式
    input wire [15:0] data_in,       // 输入数据(有符号)
    input wire [15:0] weight,        // 权重数据(有符号)
    input wire [15:0] prev_accum,    // 外部累加值（当启用乘加累积功能时使用）
    input wire clear_acc,            // 清除累加器
    input wire enable,               // 使能信号
    input wire add_only,             // 仅执行累加（a+b，跳过乘法）
    input wire use_acc,              // 使用累积模式（将结果与prev_accum相加）
    output wire [15:0] result,       // 16位计算结果
    output wire overflow_flag        // 溢出指示，用于调试
);

    //--------------------------------------------------------------------------
    // 内部信号定义
    //--------------------------------------------------------------------------
    wire [3:0] en_slice;             // 使能信号
    
    // 有符号操作数
    reg signed [7:0] a_operands [3:0];  // 操作数A (数据)
    reg signed [7:0] b_operands [3:0];  // 操作数B (权重)
    
    // 乘法结果
    wire signed [15:0] mult_results [3:0];
    
    // 累加和
    wire signed [16:0] sum_stage1_a, sum_stage1_b; // 第一级累加
    wire signed [16:0] current_sum;                // 最终结果(17位)
    wire overflow;                                 // 溢出标志
    
    // 饱和结果
    wire signed [15:0] saturated_result;
    
    // 最终结果选择
    wire signed [15:0] final_result;
    
    //--------------------------------------------------------------------------
    // 1. 模式解码和单元使能
    //--------------------------------------------------------------------------
    // 转换为组合逻辑赋值 - 考虑add_only模式
    assign en_slice = add_only ? 4'b0000 :          // 仅累加模式：禁用所有乘法单元
                     (mode == 2'b00) ? 4'b1111 :    // 4x4bit模式：所有单元使能
                     (mode == 2'b01) ? 4'b0011 :    // 2x8bit模式：前两个单元使能
                     (mode == 2'b10) ? 4'b0111 :    // 混合模式：前三个单元使能
                                       4'b0000;     // 默认:无使能
    
    //--------------------------------------------------------------------------
    // 2. 数据准备 - 根据模式提取和扩展操作数
    //--------------------------------------------------------------------------
    always @(*) begin
        // 初始化为0，避免锁存器
        a_operands[0] = 8'sh00;
        a_operands[1] = 8'sh00;
        a_operands[2] = 8'sh00;
        a_operands[3] = 8'sh00;
        b_operands[0] = 8'sh00;
        b_operands[1] = 8'sh00;
        b_operands[2] = 8'sh00;
        b_operands[3] = 8'sh00;
        
        case (mode)
            2'b00: begin // 4x4bit模式 - 符号扩展4位到8位
                a_operands[0] = {{4{data_in[3]}}, data_in[3:0]};    // 符号扩展
                a_operands[1] = {{4{data_in[7]}}, data_in[7:4]};
                a_operands[2] = {{4{data_in[11]}}, data_in[11:8]};
                a_operands[3] = {{4{data_in[15]}}, data_in[15:12]};
                
                b_operands[0] = {{4{weight[3]}}, weight[3:0]};
                b_operands[1] = {{4{weight[7]}}, weight[7:4]};
                b_operands[2] = {{4{weight[11]}}, weight[11:8]};
                b_operands[3] = {{4{weight[15]}}, weight[15:12]};
            end
            
            2'b01: begin // 2x8bit模式 - 直接使用8位数据
                a_operands[0] = data_in[7:0];
                a_operands[1] = data_in[15:8];
                
                b_operands[0] = weight[7:0];
                b_operands[1] = weight[15:8];
            end
            
            2'b10: begin // 混合模式: 2x4bit + 1x8bit
                a_operands[0] = {{4{data_in[3]}}, data_in[3:0]};    // 4bit数据
                a_operands[1] = {{4{data_in[7]}}, data_in[7:4]};
                a_operands[2] = data_in[15:8];                      // 8bit数据
                
                b_operands[0] = {{4{weight[3]}}, weight[3:0]};
                b_operands[1] = {{4{weight[7]}}, weight[7:4]};
                b_operands[2] = weight[15:8];
            end
        endcase
    end
    
    //--------------------------------------------------------------------------
    // 3. 乘法单元阵列 - 实例化4个乘法器 (保持不变，本身就是组合逻辑)
    //--------------------------------------------------------------------------
    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin: mult_units
            booth_multiplier booth_mult_inst (
                .a(a_operands[i]),
                .b(b_operands[i]),
                .mode(mode),
                .slice_id(i),
                .enable(en_slice[i]),
                .product(mult_results[i])
            );
        end
    endgenerate
    
    //--------------------------------------------------------------------------
    // 4. 累加树 - 分层设计以降低关键路径延迟，并支持仅累加模式
    //--------------------------------------------------------------------------
    // 第一级累加 - 将4个输入分成两组累加
    assign sum_stage1_a = {mult_results[0][15], mult_results[0]} + 
                          {mult_results[1][15], mult_results[1]};
                          
    assign sum_stage1_b = {mult_results[2][15], mult_results[2]} + 
                          {mult_results[3][15], mult_results[3]};
    
    // 定义仅累加模式的操作数（直接相加两个输入操作数）
    wire signed [16:0] add_only_result = {data_in[15], data_in} + {weight[15], weight};
    
    // 第二级累加 - 根据模式选择适当的累加方式
    assign current_sum = add_only ? add_only_result :               // 仅累加模式: a + b
                        (mode == 2'b01) ? sum_stage1_a :            // 2x8bit模式
                        (mode == 2'b10) ? (sum_stage1_a + {mult_results[2][15], mult_results[2]}) :  // 混合模式
                        (sum_stage1_a + sum_stage1_b);              // 4x4bit模式
    
    //--------------------------------------------------------------------------
    // 5. 溢出检测与饱和处理 (保持不变，本身就是组合逻辑)
    //--------------------------------------------------------------------------
    // 检测溢出 - 当符号位与最高有效位不一致时发生溢出
    assign overflow = (current_sum[16] != current_sum[15]);
    assign overflow_flag = overflow;  // 导出溢出标志用于调试
    
    // 饱和处理 - 溢出时截断到16位范围
    assign saturated_result = overflow ? 
                             (current_sum[16] ? 16'sh8000 : 16'sh7FFF) : // 负/正溢出
                             current_sum[15:0];                          // 无溢出
    
    //--------------------------------------------------------------------------
    // 6. 组合逻辑结果计算 - 简化为直接计算输出
    //--------------------------------------------------------------------------
    // 计算当前周期的结果
    wire signed [16:0] current_result = enable ? saturated_result : 17'sh00000;
    
    // 是否与累加值相加（只在use_acc=1时执行）
    wire signed [16:0] computation_result = (enable && use_acc && !clear_acc) ? 
                                         (current_result + {prev_accum[15], prev_accum}) : // 与累加值相加
                                         current_result;                                  // 仅使用当前结果
    
    // 检查计算结果是否溢出
    wire computation_overflow = (computation_result[16] != computation_result[15]);
    
    // 应用饱和逻辑并输出最终结果
    assign result = clear_acc ? 16'sh0000 :
                    (computation_overflow ? 
                     (computation_result[16] ? 16'sh8000 : 16'sh7FFF) : // 负/正溢出
                      computation_result[15:0]);                        // 无溢出

endmodule

//--------------------------------------------------------------------------
// 乘法器模块 - 支持4位和8位有符号乘法 (保持原设计不变)
//--------------------------------------------------------------------------
module booth_multiplier (
    input signed [7:0] a,           // 被乘数
    input signed [7:0] b,           // 乘数
    input [1:0] mode,               // 操作模式
    input [1:0] slice_id,           // 切片ID
    input enable,                   // 使能信号
    output signed [15:0] product    // 乘积结果
);
    // 确定乘法器类型
    wire use_4bit_mult = (mode == 2'b00) || 
                         ((mode == 2'b10) && (slice_id < 2));
    
    // 4位乘法与8位乘法结果
    wire signed [15:0] product_4bit, product_8bit;
    
    // 根据使能和乘法类型选择结果
    assign product = (!enable) ? 16'sh0000 :
                     use_4bit_mult ? product_4bit : product_8bit;
    
    //--------------------------------------------------------------------------
    // 4位有符号乘法实现 (基于Modified Booth算法)
    //--------------------------------------------------------------------------
    booth_4x4 booth_4bit_inst (
        .a(a[3:0]),
        .b(b[3:0]),
        .product(product_4bit)
    );
    
    //--------------------------------------------------------------------------
    // 8位有符号乘法实现 (基于Modified Booth算法与Wallace树)
    //--------------------------------------------------------------------------
    booth_8x8 booth_8bit_inst (
        .a(a),
        .b(b),
        .product(product_8bit)
    );
    
endmodule

// 其他子模块保持不变...
// booth_4x4, booth_8x8, booth_pp_gen, wallace_csa

//------------------------------------------------------------------------------
// 4x4 有符号乘法器 - 使用Modified Booth算法(Radix-2)
//------------------------------------------------------------------------------
module booth_4x4 (
    input signed [3:0] a,        // 4位有符号被乘数
    input signed [3:0] b,        // 4位有符号乘数
    output signed [15:0] product // 乘积结果，扩展到16位
);
    // 内部信号
    wire [1:0] booth_enc [1:0];  // Radix-2 Booth编码
    wire [4:0] pp [1:0];         // 部分积
    wire [8:0] shifted_pp [1:0]; // 移位后的部分积
    wire [8:0] sum;              // 最终和
    
    // 扩展操作数用于Booth编码
    wire [4:0] a_ext = {a[3], a};         // 符号扩展一位
    wire [4:0] b_ext = {b, 1'b0};         // 添加一个0位
    
    // Radix-2 Booth编码
    assign booth_enc[0] = b_ext[1:0];
    assign booth_enc[1] = b_ext[3:2];
    
    // 生成部分积
    booth_pp_gen #(
        .WIDTH(5)
    ) pp_gen0 (
        .a(a_ext),
        .enc(booth_enc[0]),
        .pp(pp[0])
    );
    
    booth_pp_gen #(
        .WIDTH(5)
    ) pp_gen1 (
        .a(a_ext),
        .enc(booth_enc[1]),
        .pp(pp[1])
    );
    
    // 移位部分积
    assign shifted_pp[0] = {4'b0000, pp[0]};
    assign shifted_pp[1] = {2'b00, pp[1], 2'b00};
    
    // 快速累加部分积
    assign sum = shifted_pp[0] + shifted_pp[1];
    
    // 结果符号扩展到16位
    assign product = {{7{sum[8]}}, sum};
    
endmodule

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
    input [WIDTH-1:0] a,      // 扩展的被乘数
    input [1:0] enc,          // Radix-2 Booth编码
    output [WIDTH-1:0] pp     // 部分积
);
    reg [WIDTH-1:0] pp_temp;
    
    // Modified Booth (Radix-2)编码逻辑
    always @(*) begin
        case (enc)
            2'b00: pp_temp = {WIDTH{1'b0}};                 // +0
            2'b11: pp_temp = {WIDTH{1'b0}};                 // +0
            2'b01: pp_temp = a;                             // +A
            2'b10: pp_temp = (~a) + {{(WIDTH-1){1'b0}}, 1'b1}; // -A
            default: pp_temp = {WIDTH{1'b0}};
        endcase
    end
    
    assign pp = pp_temp;
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

// 纯组合逻辑MAC的新包装模块
module Combinational_MAC_wrapper (
    input [7:0] alu,          // 操作码
    input signed_,            // 有符号/无符号标志 (现在忽略，固定为有符号)
    input [15:0] a,           // 第一个操作数
    input [15:0] b,           // 第二个操作数
    input [15:0] acc_in,      // 累加器输入（仅在乘加累积模式使用）
    input d,                  // 可用作额外控制
    output [15:0] O0,         // 16位结果输出
    output O1,                // 溢出标志
    output O2,                // 用于条件模块
    output O3,                // 输出MAC模式[0]
    output O4,                // 输出MAC模式[1]
    output O5,                // 输出MAC模式信息
    input CLK,                // 添加时钟信号（虽然是组合逻辑但保持接口一致）
    input ASYNCRESET,         // 添加异步复位信号（虽然是组合逻辑但保持接口一致）
    output [15:0] full_result // 扩展输出，现在限制为16位
);
    // 从原始控制信号解码新的模式
    reg [1:0] new_mode;      // 模式编码: 00:4x4bit, 01:2x8bit, 10:混合模式, 11:预留给未来扩展
    wire clear_acc;
    wire enable;
    wire add_only;           // 仅累加模式（跳过乘法）
    wire use_acc;            // 是否使用累积值
    
    // 操作码解码
    always @(*) begin
        case (alu[1:0])
            2'b00: new_mode = 2'b00;  // 4x4bit模式
            2'b01: new_mode = 2'b01;  // 2x8bit模式
            2'b10: new_mode = 2'b10;  // 混合模式(2x4bit + 1x8bit)
            2'b11: new_mode = 2'b11;  // 预留给未来扩展
            default: new_mode = 2'b00; // 默认为4x4bit模式
        endcase
    end
    
    assign clear_acc = alu[3] | d;            // 清零信号
    assign enable = alu[4];                   // 使能信号
    assign add_only = alu[5];                 // 使用独立的控制位 alu[5] 控制仅累加模式
    assign use_acc = alu[2];                  // 单独使用 alu[2] 控制是否使用累积值
    
    // 实例化纯组合逻辑MAC模块
    wire overflow_flag;
    wire [15:0] calc_result;
    
    Combinational_Subword_MAC mac_core (
        .mode(new_mode),             // 00:4x4bit, 01:2x8bit, 10:混合模式
        .data_in(a),                 // 输入数据
        .weight(b),                  // 权重数据
        .prev_accum(acc_in),         // 外部累加值（仅在乘加累积模式使用）
        .enable(enable),             // 使能信号
        .clear_acc(clear_acc),       // 清除累加器
        .add_only(add_only),         // 仅累加模式（a+b，跳过乘法）
        .use_acc(use_acc),           // 使用累积模式
        .result(calc_result),        // 16位计算结果
        .overflow_flag(overflow_flag) // 溢出指示
    );
    
    // 输出赋值 - 保持与原始接口兼容
    assign O0 = calc_result;         // 结果输出 (已经饱和处理)
    assign O1 = overflow_flag;       // 溢出标志
    assign O2 = calc_result[8];      // 用于条件模块的位
    assign O3 = new_mode[0];         // 模式位[0]
    assign O4 = new_mode[1];         // 模式位[1]
    assign O5 = add_only;            // 输出add_only模式标志
    
    // 完整结果输出
    assign full_result = calc_result;
endmodule