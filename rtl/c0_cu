module cu(
    input [31:0] instruction,
    output reg RegWrite,
    output reg imm_or_reg_select,
    output reg data_mem_read_en,
    output reg data_mem_write_en, //two because we need a neither condition
    output reg [3:0] alu_control,
    output reg data_mem_or_from_alu,
    output reg branch,
    output reg jal,
    output reg jalr
    );

    wire [6:0] opcode = instruction[6:0];
    wire [2:0] funct3 = instruction[14:12];
    wire [6:0] funct7 = instruction[31:25];
    wire [5:0] funct6 = instruction[31:26]; // RV64 shift-imm discriminator only (bit 25 is shamt[5])

    // opcode encodings (RV64I, no *w variants)
    localparam OP        = 7'b0110011; // R-type
    localparam OP_IMM     = 7'b0010011; // I-type ALU
    localparam LOAD       = 7'b0000011;
    localparam STORE      = 7'b0100011;
    localparam BRANCH     = 7'b1100011;
    localparam JAL        = 7'b1101111;
    localparam JALR       = 7'b1100111;
    localparam LUI        = 7'b0110111;
    localparam AUIPC      = 7'b0010111;

    // alu_control encodings, these are the operations alu can perform. it is unaware of any instrcution type or whatever; just tell it what to do.
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

    // coarse op class from main decoder, consumed by ALU decoder
    reg [1:0] alu_op;
    // alu_op = 00 -> force ADD (loads/stores/jalr/auipc)
    // alu_op = 01 -> force SUB (branches)
    // alu_op = 10 -> R-type: use funct3/funct7
    // alu_op = 11 -> I-type ALU (OP_IMM): use funct3/funct6 (shamt is 6 bits in RV64)

    // ---------------- Main decoder ----------------
    //here based on opcode some things are decided
    always @(*) begin
  
        RegWrite           = 1'b0;    
        imm_or_reg_select  = 1'b0;    
        data_mem_read_en   = 1'b0;    
        data_mem_write_en  = 1'b0;    
        data_mem_or_from_alu = 1'b0;  
        branch             = 1'b0;    
        jal                = 1'b0;    
        jalr               = 1'b0;
        alu_op             = 2'b00;

        case (opcode)
            OP: begin
                RegWrite          = 1'b1;
                imm_or_reg_select = 1'b0; //0 means ull be selecting reg input
                alu_op            = 2'b10;
            end

            OP_IMM: begin
                RegWrite          = 1'b1;
                imm_or_reg_select = 1'b1; //1 means ull be selecting imm input 
                alu_op            = 2'b11;
            end

            LOAD: begin //load loads the value from data mem to the reg
                RegWrite            = 1'b1; //load must ultimately write to a reg
                imm_or_reg_select   = 1'b1; //offset is involved so select imm
                data_mem_read_en    = 1'b1; // need to read data mem
                data_mem_or_from_alu = 1'b1; // this goes to reg mem, we choose data mem as source
                alu_op              = 2'b00; // address = rs1 + imm
            end

            STORE: begin //must store a value from a reg to the data mem
                imm_or_reg_select  = 1'b1; //involves offset so choose imm
                data_mem_write_en  = 1'b1; // must write to data mem
                alu_op             = 2'b00; // address = rs1 + imm
            end

            BRANCH: begin         // B type
                imm_or_reg_select = 1'b0; //compares 2 reg so have reg selected
                branch            = 1'b1; // need to branch, the other condition is evaluated in the alu
                alu_op            = 2'b01; // subtract/compare
            end

            JAL: begin            // J type
                RegWrite          = 1'b1; // PC + 4 to be written into reg
                jal               = 1'b1; // datapath: select PC+4 into writeback mux
            end

            JALR: begin           // I type
                RegWrite          = 1'b1; // rd = PC + 4
                imm_or_reg_select = 1'b1; // involves offset: x = pc + offset << 12
                alu_op            = 2'b00; // target addr = rs1 + imm
                jalr              = 1'b1; // datapath: select PC+4 into writeback mux
            end

            LUI: begin            // U type
                RegWrite          = 1'b1; // to be written to register
                imm_or_reg_select = 1'b1; // deals with offset so imm is needed
            end

            AUIPC: begin          // U type
                RegWrite          = 1'b1; // same as abv
                imm_or_reg_select = 1'b1; // same as abv
                alu_op            = 2'b00; // rd = PC + imm
            end

            default: ; // already above
        endcase
    end

    // ---------------- ALU decoder ----------------
    always @(*) begin
        case (alu_op)
            2'b00: alu_control = ALU_ADD;
            2'b01: alu_control = ALU_SUB;
            2'b10: begin
                case (funct3)
                    3'b000: alu_control = (funct7 == 7'b0100000) ? ALU_SUB : ALU_ADD; 
                    3'b001: alu_control = ALU_SLL;                                    
                    3'b010: alu_control = ALU_SLT;                                     
                    3'b011: alu_control = ALU_SLTU;                                    
                    3'b100: alu_control = ALU_XOR;                                     
                    3'b101: alu_control = (funct7 == 7'b0100000) ? ALU_SRA : ALU_SRL;  
                    3'b110: alu_control = ALU_OR;                                      
                    3'b111: alu_control = ALU_AND;                                     
                    default: alu_control = ALU_ADD;
                endcase
            end
            2'b11: begin // I-type ALU: shift-immediate uses funct6 (not funct7) - bit 25 is shamt[5] on RV64
                case (funct3)
                    3'b000: alu_control = ALU_ADD;                                     
                    3'b001: alu_control = ALU_SLL;                                     
                    3'b010: alu_control = ALU_SLT;                                      
                    3'b011: alu_control = ALU_SLTU;                                    
                    3'b100: alu_control = ALU_XOR;                                      
                    3'b101: alu_control = (funct6 == 6'b010000) ? ALU_SRA : ALU_SRL;    
                    3'b110: alu_control = ALU_OR;                                       
                    3'b111: alu_control = ALU_AND;                                     
                    default: alu_control = ALU_ADD;
                endcase
            end
            default: alu_control = ALU_ADD;
        endcase
    end

endmodule
