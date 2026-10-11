`timescale 1ns / 1ps

module pc(
    input rst, clk,
    input [63:0] from_mux,
    input pc_mux_control,
    output reg [63:0] pc,
    input stall
    );
    
    always @(posedge clk) begin
        if (rst) begin
            pc <= 64'd0;
        end
        else if (pc_mux_control) begin
            pc <= from_mux;
        end
        else if (stall) begin
            pc <= pc;
        end
        else begin
            pc <= pc + 64'd4;
        end
    end
    
endmodule
