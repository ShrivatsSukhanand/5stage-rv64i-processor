`timescale 1ns / 1ps

module store_load_module(
    input [63:0] result, // input address from the alu
    input [2:0] funct3,  // to know what type of load store
    input [63:0] data_toBeStored, //from core
    input opcode_bit, //load is 0000011 and str is 0100011
    output reg [63:0] modified_address, // goes to data mem
    output reg [63:0] modifiedDataSTORE, // to be stored into data mem
    output reg [7:0] byte_enable // to data mem
    );
    
    wire [2:0] result_b = result[2:0];
    wire [1:0] result_h = result[2:1];

wire [5:0] byte_shift = {result[2:0], 3'b000};
wire [5:0] half_shift = {result[2:1], 4'b0000};
wire [5:0] word_shift = {result[2],   5'b00000};

wire [63:0] y1 = (data_toBeStored & 64'hFF)
                  << byte_shift;

wire [63:0] y2 = (data_toBeStored & 64'hFFFF)
                  << half_shift;

wire [63:0] y3 = (data_toBeStored & 64'hFFFFFFFF)
                  << word_shift;

wire [63:0] y4 = data_toBeStored;

    always @(*) begin
        modified_address = result >> 3;
    end
      
    always @(*) begin
        
        modifiedDataSTORE = 64'b0;
        byte_enable = 8'b0;
        
        case(funct3)
        
        3'b000 : begin // for byte
            if(opcode_bit) begin // processor -> data
                modifiedDataSTORE = y1; //byte it is
                byte_enable = 8'b00000001 << result_b;
            end
        end

        3'b001 : begin // for half
            if(opcode_bit) begin // processor -> data
                modifiedDataSTORE = y2; //half it is
                byte_enable = 8'b00000011 << {result_h,1'b0};
            end
        end
        
        3'b010 : begin // for word
            if(opcode_bit) begin // processor -> data
                modifiedDataSTORE = y3; //word it is
                byte_enable = 8'b00001111 << {result[2],2'b00};
            end
        end
        
        3'b011 : begin // for doubleword
            if(opcode_bit) begin // processor -> data
                modifiedDataSTORE = y4; //dword it is
                byte_enable = 8'b11111111;
            end
        end

        endcase
    
    end
    
endmodule
