`timescale 1ns / 1ps

module core(
    input clk, rst,
    output ex_mem_N, ex_mem_Z, ex_mem_C, ex_mem_V 
);

reg [95:0] IF_ID;
reg [285:0] ID_EX; 
reg [220:0] EX_MEM;   
reg [135:0] MEM_WB;   

wire N, Z, C, V;
wire stall;
wire [31:0] instruction;
wire [63:0] pcounter;
wire [4:0] rs1, rs2, rd;
wire [63:0] imm_gen_value;
wire [63:0] new_pc;
wire [63:0] result;
wire pc_mux_control;
wire branch_cond_ok;
wire [63:0] regVSimm;
wire [7:0]  byte_enable;
wire [63:0] modified_address;
wire [63:0] modifiedDataSTORE;
wire [63:0] modifiedDataLOAD;
wire [63:0] data_toBeLoaded;
wire [63:0] ex_mem_alu_result; // for to store in reg
wire [2:0] AmuxSel;
wire [2:0] BmuxSel;
wire [63:0] read_data1;
wire [63:0] read_data2;
wire [63:0] which_data;
wire [2:0] SmuxSel;
wire [63:0] store_data_forwarded;

//FOR CU
wire RegWrite;
wire imm_or_reg_select;
wire data_mem_read_en;
wire data_mem_write_en;
wire [3:0] alu_control;
wire data_mem_or_from_alu;
wire branch;
wire jal;
wire jalr;

// ---------- IF/ID extracted fields ----------
wire [63:0] if_id_pc     = IF_ID[95:32];
wire [31:0] if_id_instr  = IF_ID[31:0];

// ---------- ID/EX extracted fields ----------
wire [4:0] id_ex_rs1            = ID_EX[285:281];
wire [4:0] id_ex_rs2            = ID_EX[280:276];
wire id_ex_RegWrite             = ID_EX[275];
wire id_ex_imm_or_reg_select    = ID_EX[274];
wire id_ex_data_mem_read_en     = ID_EX[273];
wire id_ex_data_mem_write_en    = ID_EX[272];
wire [3:0] id_ex_alu_control    = ID_EX[271:268];
wire id_ex_data_mem_or_from_alu = ID_EX[267];
wire id_ex_branch               = ID_EX[266];
wire id_ex_CTRL_jal             = ID_EX[265];
wire [4:0] id_ex_rd             = ID_EX[264:260];
wire id_ex_opcode_bit           = ID_EX[259];
wire [2:0]  id_ex_funct3        = ID_EX[258:256];
wire [63:0] id_ex_pc            = ID_EX[255:192];
wire [63:0] id_ex_rs1_data      = ID_EX[191:128];
wire [63:0] id_ex_rs2_data      = ID_EX[127:64];
wire [63:0] id_ex_imm           = ID_EX[63:0];

// ---------- EX/MEM extracted fields ----------
wire [4:0] ex_mem_rs1             = EX_MEM[220:216];
wire [4:0] ex_mem_rs2             = EX_MEM[215:211];
wire ex_mem_RegWrite              = EX_MEM[210];
wire ex_mem_data_mem_read_en      = EX_MEM[209];
wire ex_mem_data_mem_write_en     = EX_MEM[208];
wire ex_mem_data_mem_or_from_alu  = EX_MEM[207];
wire ex_mem_CTRL_jal              = EX_MEM[206];
wire [4:0] ex_mem_rd              = EX_MEM[205:201];
wire ex_mem_opcode_bit            = EX_MEM[200];
wire [2:0] ex_mem_funct3          = EX_MEM[199:197];
wire [63:0] ex_mem_result         = EX_MEM[196:133];
wire ex_mem_pc_mux_control        = EX_MEM[132];
wire [63:0] ex_mem_new_pc         = EX_MEM[131:68];
assign ex_mem_N                   = EX_MEM[67];
assign ex_mem_Z                   = EX_MEM[66];
assign ex_mem_C                   = EX_MEM[65];
assign ex_mem_V                   = EX_MEM[64];
wire [63:0] ex_mem_store_data     = EX_MEM[63:0];  //rs2 carried forwared for store

// ---------- MEM/WB extracted fields ----------
wire mem_wb_RegWrite              = MEM_WB[135];
wire mem_wb_data_mem_or_from_alu  = MEM_WB[134];
wire [4:0] mem_wb_rd              = MEM_WB[132:128];
wire [63:0] mem_wb_mem_data       = MEM_WB[127:64];
wire [63:0] mem_wb_alu_result     = MEM_WB[63:0];
 
wire uses_rs1 =
    (if_id_instr[6:0] == 7'b0110011) ||  // R-type
    (if_id_instr[6:0] == 7'b0010011) ||  // I-type ALU
    (if_id_instr[6:0] == 7'b0000011) ||  // Load
    (if_id_instr[6:0] == 7'b0100011) ||  // Store
    (if_id_instr[6:0] == 7'b1100011) ||  // Branch
    (if_id_instr[6:0] == 7'b1100111);    // JALR

wire uses_rs2 =
    (if_id_instr[6:0] == 7'b0110011) ||  // R-type
    (if_id_instr[6:0] == 7'b0100011) ||  // Store
    (if_id_instr[6:0] == 7'b1100011);    // Branch
    
assign stall = id_ex_data_mem_read_en &&
               (id_ex_rd != 5'd0) &&
               ((uses_rs1 && (id_ex_rd == rs1)) ||
                (uses_rs2 && (id_ex_rd == rs2)));

wire [63:0] regVSimm1;
wire [63:0] regVSimm2;

wire branch_taken = id_ex_branch && branch_cond_ok;

assign which_data =
    mem_wb_data_mem_or_from_alu ? mem_wb_mem_data : mem_wb_alu_result;

assign regVSimm1 =
       (AmuxSel == 3'b001) ? id_ex_rs1_data :
       (AmuxSel == 3'b010) ? ex_mem_result  :
       (AmuxSel == 3'b100) ? which_data     :
                             id_ex_rs1_data;

assign regVSimm2 =
       (BmuxSel == 3'b001) ? id_ex_rs2_data :
       (BmuxSel == 3'b010) ? ex_mem_result  :
       (BmuxSel == 3'b100) ? which_data     :
                             id_ex_rs2_data;
       
cu f0 (
    .instruction             (if_id_instr),
    .RegWrite                (RegWrite),
    .imm_or_reg_select       (imm_or_reg_select),
    .data_mem_read_en        (data_mem_read_en),
    .data_mem_write_en       (data_mem_write_en),
    .alu_control             (alu_control),
    .data_mem_or_from_alu    (data_mem_or_from_alu),
    .branch                  (branch),
    .jal                     (jal),
    .jalr                    (jalr)
);
                     
wire [2:0] funct3;
wire opcode_bit;

assign opcode_bit = if_id_instr[5];
assign rd         = if_id_instr[11:7];
assign funct3     = if_id_instr[14:12];
assign rs1        = if_id_instr[19:15];
assign rs2        = if_id_instr[24:20];
       
pc f1 (
    .rst                (rst),
    .clk                (clk),
    .from_mux           (ex_mem_new_pc),
    .pc_mux_control     (ex_mem_pc_mux_control),
    .pc                 (pcounter),
    .stall              (stall)
);

instr_mem f2 (
    .pc                 (pcounter),
    .instruction        (instruction)
);

assign new_pc = id_ex_pc + id_ex_imm;

assign pc_mux_control = (id_ex_branch & branch_cond_ok) | jal | jalr;

imm_gen f5 (
    .instruction        (if_id_instr),
    .immediate          (imm_gen_value)
);

assign regVSimm = id_ex_imm_or_reg_select ? id_ex_imm : regVSimm2;

main_ALU f6 (
    .A              (regVSimm1),
    .B              (regVSimm),
    .alu_control    (id_ex_alu_control),
    .funct3         (id_ex_funct3),
    .result         (result),
    .N              (N),
    .V              (V),
    .C              (C),
    .Z              (Z),
    .branch_cond_ok (branch_cond_ok)
);

store_load_module f7 (
    .result             (ex_mem_result),
    .funct3             (ex_mem_funct3),
    .data_toBeStored    (ex_mem_store_data),
    .opcode_bit         (ex_mem_opcode_bit),
    .modified_address   (modified_address),
    .modifiedDataSTORE  (modifiedDataSTORE),
    .byte_enable        (byte_enable)
);

data_memory f8 (
    .clk                (clk),
    .write_enable       (ex_mem_data_mem_write_en),
    .read_enable        (ex_mem_data_mem_read_en),
    .byte_enable        (byte_enable),
    .address            (modified_address),
    .write_data         (modifiedDataSTORE),
    .read_data          (data_toBeLoaded)
);

wire [2:0] ex_mem_result_3bits = ex_mem_result[2:0];

load_extract f81 (
    .data_toBeLoaded    (data_toBeLoaded),
    .funct3             (ex_mem_funct3),
    .addr_offset        (ex_mem_result_3bits),
    .modifiedDataLOAD   (modifiedDataLOAD)
);

reg_file f9 (
    .clk                (clk),
    .rst                (rst),
    .RegWrite           (mem_wb_RegWrite),
    .read_reg1          (rs1),
    .read_reg2          (rs2),
    .read_data1         (read_data1),
    .read_data2         (read_data2),
    .write_reg          (mem_wb_rd),
    .write_data         (which_data)
);

assign store_data_forwarded =
       (SmuxSel == 3'b001) ? id_ex_rs2_data :
       (SmuxSel == 3'b010) ? ex_mem_result  :
       (SmuxSel == 3'b100) ? which_data     :
                             id_ex_rs2_data;
                             
hazard_forward hf10 (
    .id_ex_rs1             (id_ex_rs1),
    .id_ex_rs2             (id_ex_rs2),
    .ex_mem_rd             (ex_mem_rd),
    .mem_wb_rd             (mem_wb_rd),
    .ex_mem_RegWrite       (ex_mem_RegWrite),
    .mem_wb_RegWrite       (mem_wb_RegWrite),
    .id_ex_data_mem_write_en(id_ex_data_mem_write_en),
    .AmuxSel               (AmuxSel),
    .BmuxSel               (BmuxSel),
    .SmuxSel               (SmuxSel)
);
                     
// SACRED ALWAYS BLOCK 
    always @(posedge clk) begin
    
        if (rst) begin
            IF_ID  <= 96'b0;
            ID_EX  <= 286'b0;
            EX_MEM <= 221'b0;
            MEM_WB <= 136'b0;
        end
        
        else begin
         if (branch_taken || ex_mem_pc_mux_control) begin
             IF_ID <= {pcounter, 32'h00000013};  // Insert NOP
         end
         else if (!stall) begin
             IF_ID[95:32] <= pcounter;
             IF_ID[31:0]  <= instruction;
         end
         
         // make this part nop for load hazard by making control signals zero.
         ID_EX[285:281]   <= rs1;
         ID_EX[280:276]   <= rs2;
         ID_EX[275]       <= RegWrite & !stall & !branch_taken;
         ID_EX[274]       <= imm_or_reg_select & !stall & !branch_taken;
         ID_EX[273]       <= data_mem_read_en & !stall & !branch_taken;
         ID_EX[272]       <= data_mem_write_en & !stall & !branch_taken;
         ID_EX[271:268]   <= alu_control & {4{!stall & !branch_taken}};
         ID_EX[267]       <= data_mem_or_from_alu & !stall & !branch_taken;
         ID_EX[266]       <= branch & !stall & !branch_taken;
         ID_EX[265]       <= jal & !stall & !branch_taken;
         ID_EX[264:260]   <= rd;
         ID_EX[259]       <= opcode_bit & !stall & !branch_taken;
         ID_EX[258:256]   <= funct3 & {3{!stall && !branch_taken}};       //3 bits
         ID_EX[255:192]   <= if_id_pc;       //pcounter hai ye... 64 bits
         ID_EX[191:128]   <= read_data1;     //64 bits
         ID_EX[127:64]    <= read_data2;     //64 bits
         ID_EX[63:0]      <= imm_gen_value;  //64 bits
         
         EX_MEM[220:216]  <= id_ex_rs1;
         EX_MEM[215:211]  <= id_ex_rs2;
         EX_MEM[210]      <= id_ex_RegWrite;
         EX_MEM[209]      <= id_ex_data_mem_read_en;
         EX_MEM[208]      <= id_ex_data_mem_write_en;
         EX_MEM[207]      <= id_ex_data_mem_or_from_alu;
         EX_MEM[206]      <= id_ex_CTRL_jal;
         EX_MEM[205:201]  <= id_ex_rd;
         EX_MEM[200]      <= id_ex_opcode_bit;
         EX_MEM[199:197]  <= id_ex_funct3;
         EX_MEM[196:133]  <= result;
         EX_MEM[132]      <= pc_mux_control;
         EX_MEM[131:68]   <= new_pc;  //this is the output from br_jal_jalr module
         EX_MEM[67]       <= N;
         EX_MEM[66]       <= Z;
         EX_MEM[65]       <= C;
         EX_MEM[64]       <= V;  //1 bit
         EX_MEM[63:0]     <= store_data_forwarded; //rs2 is carried forward, has data to be stored
         
         MEM_WB[135]      <= ex_mem_RegWrite;
         MEM_WB[134]      <= ex_mem_data_mem_or_from_alu;
         MEM_WB[133]      <= ex_mem_CTRL_jal;
         MEM_WB[132:128]  <= ex_mem_rd;
         MEM_WB[127:64]   <= modifiedDataLOAD;   //data from the data mem 
         MEM_WB[63:0]     <= ex_mem_result; //r-r storage data
         end
    end

endmodule
