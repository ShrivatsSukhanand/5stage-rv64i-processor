module data_memory(
    input clk,
    input write_enable,
    input read_enable,
    input [7:0] byte_enable,
    input [63:0] address,
    input [63:0] write_data,
    output wire [63:0] read_data
);

    reg [63:0] mem [0:511];
    
    integer i;
    
    initial begin
        for (i = 0; i < 512; i = i + 1)
            mem[i] = 64'b0;
    
        $readmemb("E:/risc/data_list.txt", mem);
    end

    always @(posedge clk) begin
        if (write_enable && !read_enable) begin
            for (i = 0; i < 8; i = i + 1) begin
                if (byte_enable[i])
                    mem[address][i*8 +: 8] <= write_data[i*8 +: 8];
            end
        end
    end

    assign read_data =
        (read_enable && !write_enable) ? mem[address] : 64'b0;

endmodule
