`timescale 1ns / 1ps

module imm_gen(
    input [31:0] instruction,
    output reg [63:0] immediate
    );

    wire [6:0] opcode = instruction[6:0];

    // opcode encodings 
    localparam OP_IMM  = 7'b0010011; // I-type ALU
    localparam LOAD    = 7'b0000011; // I-type load
    localparam JALR    = 7'b1100111; // I-type jump
    localparam STORE   = 7'b0100011; // S-type
    localparam BRANCH  = 7'b1100011; // B-type
    localparam LUI     = 7'b0110111; // U-type
    localparam AUIPC   = 7'b0010111; // U-type
    localparam JAL     = 7'b1101111; // J-type

    always @(*) begin
        case(opcode)

            OP_IMM, LOAD, JALR: begin // I-type
                immediate = { {52{instruction[31]}}, instruction[31:20] };
            end

            STORE: begin // S-type
                immediate = { {52{instruction[31]}}, instruction[31:25], instruction[11:7] };
            end

            BRANCH: begin // B-type
                immediate = { {51{instruction[31]}}, instruction[31], instruction[7],
                              instruction[30:25], instruction[11:8], 1'b0 };
            end

            LUI, AUIPC: begin // U-type - no sign-extension... lower 12 bits are zero
                immediate = { {32{instruction[31]}}, instruction[31:12], 12'b0 };
            end

            JAL: begin // J-type
                immediate = { {43{instruction[31]}}, instruction[31], instruction[19:12],
                              instruction[20], instruction[30:21], 1'b0 };
            end

            default: immediate = 64'b0; // R-type 

        endcase
    end

endmodule
