
`timescale 1ns / 1ps

module load_extract(
    input  [63:0] data_toBeLoaded,
    input  [2:0]  funct3,
    input  [2:0]  addr_offset,
    output reg [63:0] modifiedDataLOAD
);
  
    wire [5:0] byte_shift = {addr_offset, 3'b000};
    wire [5:0] half_shift = {addr_offset[2:1], 4'b0000};
    wire [5:0] word_shift = {addr_offset[2], 5'b00000};

    wire [63:0] x1 =
        (data_toBeLoaded >> byte_shift) & 64'h00000000000000FF;

    wire [63:0] x2 =
        (data_toBeLoaded >> half_shift) & 64'h000000000000FFFF;

    wire [63:0] x3 =
        (data_toBeLoaded >> word_shift) & 64'h00000000FFFFFFFF;
    
    wire [63:0] x4 = data_toBeLoaded;

    always @(*) begin
        modifiedDataLOAD = 64'b0;

        case (funct3)
            3'b000: modifiedDataLOAD = {{56{x1[7]}},  x1[7:0]};   // LB
            3'b001: modifiedDataLOAD = {{48{x2[15]}}, x2[15:0]};  // LH
            3'b010: modifiedDataLOAD = {{32{x3[31]}}, x3[31:0]};  // LW
            3'b011: modifiedDataLOAD = data_toBeLoaded;           // LD
            default: modifiedDataLOAD = 64'b0;
        endcase
    end

endmodule
