`timescale 1ns / 1ps

module reg_file(
    input clk, rst,
    input RegWrite,            // write enable
    
    input [4:0] read_reg1,     // r1
    input [4:0] read_reg2,     // r2
    output [63:0] read_data1,  // read data 1
    output [63:0] read_data2,  // read data 2
    
    input [4:0] write_reg,     // rd
    input [63:0] write_data    // what data u wanna write
    );

    reg [63:0] r [0:31];

    // combinational read - r0 always reads as 0
    assign read_data1 =
    (read_reg1 == 5'd0) ? 64'd0 :
    (RegWrite && write_reg != 5'd0 && write_reg == read_reg1)
        ? write_data :
          r[read_reg1];

    assign read_data2 =
    (read_reg2 == 5'd0) ? 64'd0 :
    (RegWrite && write_reg != 5'd0 && write_reg == read_reg2)
        ? write_data :
          r[read_reg2];

  integer i;

always @(posedge clk) begin
    if (rst) begin
        for (i = 0; i < 32; i = i + 1)
            r[i] <= 64'b0;
    end
    else if (RegWrite && write_reg != 5'd0) begin
        r[write_reg] <= write_data;
    end
end

endmodule
