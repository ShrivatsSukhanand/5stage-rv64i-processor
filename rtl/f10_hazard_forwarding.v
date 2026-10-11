`timescale 1ns / 1ps

module hazard_forward(
    input [4:0] id_ex_rs1, id_ex_rs2,
    input [4:0] ex_mem_rd, mem_wb_rd,
    input       ex_mem_RegWrite,
    input       mem_wb_RegWrite,
    input id_ex_data_mem_write_en,
    output reg [2:0] AmuxSel, BmuxSel, SmuxSel
);
    
always @(*) begin
    AmuxSel = 3'b001;
    BmuxSel = 3'b001;
    SmuxSel = 3'b001;
    // A operand
    if (ex_mem_RegWrite && (ex_mem_rd != 5'd0) && 
        (id_ex_rs1 == ex_mem_rd))
        AmuxSel = 3'b010;
    else if (mem_wb_RegWrite && (mem_wb_rd != 5'd0) && 
             (id_ex_rs1 == mem_wb_rd))
        AmuxSel = 3'b100;

    // B operand
    if (ex_mem_RegWrite && (ex_mem_rd != 5'd0) && 
        (id_ex_rs2 == ex_mem_rd))
        BmuxSel = 3'b010;
    else if (mem_wb_RegWrite && (mem_wb_rd != 5'd0) && 
             (id_ex_rs2 == mem_wb_rd))
        BmuxSel = 3'b100;
        
    // store data forwarding
    if (id_ex_data_mem_write_en &&
        ex_mem_RegWrite &&
        (ex_mem_rd != 5'd0) &&
        (id_ex_rs2 == ex_mem_rd))
        SmuxSel = 3'b010;

    else if (id_ex_data_mem_write_en &&
        mem_wb_RegWrite &&
        (mem_wb_rd != 5'd0) &&
        (id_ex_rs2 == mem_wb_rd))
        SmuxSel = 3'b100;
end

endmodule
