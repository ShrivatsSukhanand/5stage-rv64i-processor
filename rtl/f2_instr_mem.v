`timescale 1ns / 1ps

module instr_mem(
    input [63:0] pc,
    output [31:0] instruction
    );
    
    reg [31:0] instr_mem_256 [0:255];
    initial $readmemb("E:/risc/instr_list.txt", instr_mem_256);
    
  assign instruction = instr_mem_256[pc[9:2]]; // 9:2 instead of 7:0 because we need multiple of +4
endmodule
