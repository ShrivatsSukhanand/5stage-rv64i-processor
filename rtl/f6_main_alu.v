`timescale 1ns / 1ps

module main_ALU(
    input [63:0] A, B,
    input [3:0] alu_control,
    input [2:0] funct3,
    output reg [63:0] result,
    output reg N, V, C, Z, branch_cond_ok
    );
    
    localparam ALU_ADD  = 4'b0000;
    localparam ALU_SUB  = 4'b0001;
    
    localparam ALU_AND  = 4'b0010;
    localparam ALU_OR   = 4'b0011;
    localparam ALU_XOR  = 4'b0100;
    
    localparam ALU_SLL  = 4'b0101;
    localparam ALU_SRL  = 4'b0110;
    localparam ALU_SRA  = 4'b0111;
    
    localparam ALU_SLT  = 4'b1000;
    localparam ALU_SLTU = 4'b1001; 
    
    
    always@(*) begin
        C = 1'b0;

        case(alu_control) 
        
        ALU_ADD: begin
            {C,result} = {1'b0,A} + {1'b0,B};
        end
        
        ALU_SUB: begin
            {C,result} = {1'b0,A} + ~{1'b0,B} + 1'b1;
        end
        
        ALU_AND: begin
            result = A & B;
        end
        
        ALU_OR: begin
            result = A | B;
        end
        
        ALU_XOR: begin
            result = A ^ B;
        end
        
        ALU_SLL: begin
            result = A << B[5:0];
        end
        
        ALU_SRL: begin
            result = A >> B[5:0];
        end
        
        ALU_SRA: begin
            result = $signed(A) >>> B[5:0];
        end
        
        ALU_SLT: begin
            if($signed(A) < $signed(B)) result = 1'b1;
            else result = 1'b0;
        end
        
        ALU_SLTU: begin
            if(A < B) result = 1'b1;
            else result = 1'b0;
        end
        
        default: result = 64'b0;
        
        endcase
    end
    
    always @(*) begin
        N = result[63];
        Z = (result == 64'b0);

        if (alu_control == ALU_ADD)
            V = (~(A[63] ^ B[63])) & (A[63] ^ result[63]);
        else if (alu_control == ALU_SUB)
            V = (A[63] ^ B[63]) & (A[63] ^ result[63]);
        else
            V = 1'b0;
    end
    
    always @(*) begin
        case (funct3)
            3'b000: branch_cond_ok = Z;          // BEQ
            3'b001: branch_cond_ok = ~Z;         // BNE
            3'b100: branch_cond_ok = N ^ V;      // BLT
            3'b101: branch_cond_ok = ~(N ^ V);   // BGE
            3'b110: branch_cond_ok = ~C;         // BLTU
            3'b111: branch_cond_ok = C;          // BGEU
            default: branch_cond_ok = 1'b0;
        endcase
    end
    
endmodule
