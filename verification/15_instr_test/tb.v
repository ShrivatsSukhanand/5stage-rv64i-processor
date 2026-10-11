`timescale 1ns / 1ps

module tb_core;

    // Deterministic 15-word verification program; no random stimulus.
    localparam integer TEST_CYCLES          = 40;
    localparam integer PROGRAM_WORDS         = 15;
    localparam integer DMEM_WORDS            = 512;
    localparam integer EXPECTED_WB_EVENTS    = 7;
    localparam integer EXPECTED_STORE_EVENTS = 3;
    localparam integer EXPECTED_BRANCHES     = 3;
    localparam integer EXPECTED_REDIRECTS    = 2;
    localparam integer EXPECTED_LOAD_STALLS  = 1;

    reg clk;
    reg rst;

    wire ex_mem_N;
    wire ex_mem_Z;
    wire ex_mem_C;
    wire ex_mem_V;

    integer i;
    integer k;
    integer reg_idx;

    integer instruction_errors;
    integer wb_errors;
    integer store_errors;
    integer branch_errors;
    integer redirect_errors;
    integer redirect_pc_errors;
    integer pc_step_errors;
    integer stall_errors;
    integer reg_errors;
    integer mem_errors;
    integer wrong_path_wb_errors;

    integer wb_seen;
    integer store_seen;
    integer branch_seen;
    integer redirect_seen;
    integer stall_seen;
    integer pc_step_count;
    integer taken_branches;
    integer not_taken_branches;

    integer saw_exmem_store_forward;
    integer saw_memwb_store_forward;

    reg [31:0] expected_instr [0:PROGRAM_WORDS-1];
    reg [4:0]  expected_wb_rd [0:EXPECTED_WB_EVENTS-1];
    reg [63:0] expected_wb_data [0:EXPECTED_WB_EVENTS-1];
    reg [63:0] expected_store_index [0:EXPECTED_STORE_EVENTS-1];
    reg [63:0] expected_store_data [0:EXPECTED_STORE_EVENTS-1];
    reg [63:0] expected_reg [0:31];
    reg [63:0] expected_mem [0:DMEM_WORDS-1];

    reg [63:0] b_pc;
    reg [63:0] b_rs1;
    reg [63:0] b_rs2;
    reg [63:0] b_target_calc;
    reg [63:0] b_expected_rs1;
    reg [63:0] b_expected_rs2;
    reg [63:0] b_expected_target;
    reg [2:0]  b_expected_funct3;
    reg        b_expected_taken;
    reg        b_pc_known;

    reg [63:0] redirect_expected_target;
    reg [63:0] pending_target;
    reg [63:0] pc_before;
    reg [63:0] pc_expected_next;
    reg        redirect_pending;

    // ------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------

    core uut (
        .clk      (clk),
        .rst      (rst),
        .ex_mem_N (ex_mem_N),
        .ex_mem_Z (ex_mem_Z),
        .ex_mem_C (ex_mem_C),
        .ex_mem_V (ex_mem_V)
    );

    always #10 clk = ~clk;

    // ------------------------------------------------------------
    // Register checker
    // ------------------------------------------------------------

    task check_reg;
        input integer index;
        input [63:0] expected;
        begin
            if (uut.f9.r[index] !== expected) begin
                $display("[FAIL REG] x%0d expected=%016h actual=%016h",
                         index, expected, uut.f9.r[index]);
                reg_errors = reg_errors + 1;
            end
            else begin
                $display("[PASS REG] x%0d = %016h", index, uut.f9.r[index]);
            end
        end
    endtask

    // ------------------------------------------------------------
    // Initialize program expectations, memory, and reference model
    // ------------------------------------------------------------

    initial begin
        clk = 1'b0;
        rst = 1'b1;

        instruction_errors = 0;
        wb_errors = 0;
        store_errors = 0;
        branch_errors = 0;
        redirect_errors = 0;
        redirect_pc_errors = 0;
        pc_step_errors = 0;
        stall_errors = 0;
        reg_errors = 0;
        mem_errors = 0;
        wrong_path_wb_errors = 0;

        wb_seen = 0;
        store_seen = 0;
        branch_seen = 0;
        redirect_seen = 0;
        stall_seen = 0;
        pc_step_count = 0;
        taken_branches = 0;
        not_taken_branches = 0;
        saw_exmem_store_forward = 0;
        saw_memwb_store_forward = 0;

        redirect_pending = 1'b0;
        pending_target = 64'd0;
        b_pc_known = 1'b0;

        // Exact words generated and checked from branch_memory_test.s.
        expected_instr[0]  = 32'h00003083; // LD   x1, 0(x0)
        expected_instr[1]  = 32'h00800513; // ADDI x10, x0, 8
        expected_instr[2]  = 32'h00803103; // LD   x2, 8(x0)
        expected_instr[3]  = 32'h002081B3; // ADD  x3, x1, x2
        expected_instr[4]  = 32'h04303023; // SD   x3, 64(x0)
        expected_instr[5]  = 32'h00119213; // SLLI x4, x3, 1
        expected_instr[6]  = 32'h00B00593; // ADDI x11, x0, 11
        expected_instr[7]  = 32'h04403423; // SD   x4, 72(x0)
        expected_instr[8]  = 32'h004183B3; // ADD  x7, x3, x4
        expected_instr[9]  = 32'h00108463; // BEQ  x1, x1, +8
        expected_instr[10] = 32'h06300893; // ADDI x17, x0, 99 (wrong path)
        expected_instr[11] = 32'h00109463; // BNE  x1, x1, +8 (not taken; target PC 52)
        expected_instr[12] = 32'h00209463; // BNE  x1, x2, +8 (taken)
        expected_instr[13] = 32'h06300913; // ADDI x18, x0, 99 (wrong path)
        expected_instr[14] = 32'h04703823; // SD   x7, 80(x0)

        // Ordered architectural writeback reference.
        expected_wb_rd[0] = 5'd1;  expected_wb_data[0] = 64'd5;
        expected_wb_rd[1] = 5'd10; expected_wb_data[1] = 64'd8;
        expected_wb_rd[2] = 5'd2;  expected_wb_data[2] = 64'd7;
        expected_wb_rd[3] = 5'd3;  expected_wb_data[3] = 64'd12;
        expected_wb_rd[4] = 5'd4;  expected_wb_data[4] = 64'd24;
        expected_wb_rd[5] = 5'd11; expected_wb_data[5] = 64'd11;
        expected_wb_rd[6] = 5'd7;  expected_wb_data[6] = 64'd36;

        // Store address is checked as the 64-bit word index used by data_memory.
        expected_store_index[0] = 64'd8;
        expected_store_data[0]  = 64'd12;
        expected_store_index[1] = 64'd9;
        expected_store_data[1]  = 64'd24;
        expected_store_index[2] = 64'd10;
        expected_store_data[2]  = 64'd36;

        // Wait for the DUT's initial $readmemb, then set all RAM words explicitly.
        #1;
        for (i = 0; i < DMEM_WORDS; i = i + 1) begin
            uut.f8.mem[i] = 64'd0;
            expected_mem[i] = 64'd0;
        end

        // Fixed input data; no random generator or seed is involved.
        uut.f8.mem[0] = 64'd5;
        uut.f8.mem[1] = 64'd7;
        expected_mem[0] = 64'd5;
        expected_mem[1] = 64'd7;

        // Expected results from the independent arithmetic model.
        expected_mem[8]  = 64'd12;
        expected_mem[9]  = 64'd24;
        expected_mem[10] = 64'd36;

        for (i = 0; i < 32; i = i + 1)
            expected_reg[i] = 64'd0;
        expected_reg[1]  = 64'd5;
        expected_reg[2]  = 64'd7;
        expected_reg[3]  = 64'd12;
        expected_reg[4]  = 64'd24;
        expected_reg[7]  = 64'd36;
        expected_reg[10] = 64'd8;
        expected_reg[11] = 64'd11;

        $display("====================================================");
        $display(" RV64I 15-WORD PIPELINE / MEMORY VERIFICATION");
        $display(" Instructions: LD, ADD, SD, SLLI, ADDI, BEQ, BNE");
        $display(" Input: mem[0]=5, mem[1]=7");
        $display(" Expected writes=7; stores=3; branches=3; redirects=2; load-use stalls=1");
        $display("====================================================");

        $display("Expected final registers: x1=5 x2=7 x3=12 x4=24 x7=36 x10=8 x11=11");
        $display("Expected memory: mem[8]=12 mem[9]=24 mem[10]=36");

        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        $display("[%0t] Reset released.", $time);

        repeat (TEST_CYCLES) @(posedge clk);
        #2;

        // --------------------------------------------------------
        // Final architectural register checks
        // --------------------------------------------------------
        $display("");
        $display("========== FINAL REGISTER CHECKS ==========");
        for (reg_idx = 0; reg_idx < 32; reg_idx = reg_idx + 1)
            check_reg(reg_idx, expected_reg[reg_idx]);

        // --------------------------------------------------------
        // Compare all RAM words, not just written locations
        // --------------------------------------------------------
        $display("");
        $display("========== FULL DATA-MEMORY CHECK ==========");
        for (k = 0; k < DMEM_WORDS; k = k + 1) begin
            if (uut.f8.mem[k] !== expected_mem[k]) begin
                $display("[FAIL MEM] mem[%0d] expected=%016h actual=%016h",
                         k, expected_mem[k], uut.f8.mem[k]);
                mem_errors = mem_errors + 1;
            end
        end
        if (mem_errors == 0)
            $display("[PASS MEM] All 512 data-memory words match the reference model.");

        // --------------------------------------------------------
        // Explicit event-count and coverage assertions
        // --------------------------------------------------------
        if (wb_seen != EXPECTED_WB_EVENTS) begin
            $display("[FAIL COUNT] writebacks=%0d expected=%0d", wb_seen, EXPECTED_WB_EVENTS);
            wb_errors = wb_errors + 1;
        end
        if (store_seen != EXPECTED_STORE_EVENTS) begin
            $display("[FAIL COUNT] stores=%0d expected=%0d", store_seen, EXPECTED_STORE_EVENTS);
            store_errors = store_errors + 1;
        end
        if (branch_seen != EXPECTED_BRANCHES || taken_branches != 2 || not_taken_branches != 1) begin
            $display("[FAIL COUNT] branches=%0d taken=%0d not_taken=%0d", branch_seen, taken_branches, not_taken_branches);
            branch_errors = branch_errors + 1;
        end
        if (redirect_seen != EXPECTED_REDIRECTS) begin
            $display("[FAIL COUNT] redirects=%0d expected=%0d", redirect_seen, EXPECTED_REDIRECTS);
            redirect_errors = redirect_errors + 1;
        end
        if (stall_seen != EXPECTED_LOAD_STALLS) begin
            $display("[FAIL COUNT] load-use stalls=%0d expected=%0d", stall_seen, EXPECTED_LOAD_STALLS);
            stall_errors = stall_errors + 1;
        end
        if (!saw_exmem_store_forward) begin
            $display("[FAIL COVERAGE] EX/MEM store-data forwarding was not observed.");
            store_errors = store_errors + 1;
        end
        if (!saw_memwb_store_forward) begin
            $display("[FAIL COVERAGE] MEM/WB store-data forwarding was not observed.");
            store_errors = store_errors + 1;
        end

        // --------------------------------------------------------
        // Final assertion summary
        // --------------------------------------------------------
        $display("");
        $display("========== PIPELINE / CONTROL ASSERTIONS ==========");
        $display("Instruction-image errors : %0d", instruction_errors);
        $display("Writebacks               : %0d expected %0d", wb_seen, EXPECTED_WB_EVENTS);
        $display("Stores                   : %0d expected %0d", store_seen, EXPECTED_STORE_EVENTS);
        $display("Branches                 : %0d expected %0d", branch_seen, EXPECTED_BRANCHES);
        $display("Taken / not taken        : %0d / %0d expected 2 / 1", taken_branches, not_taken_branches);
        $display("Redirects                : %0d expected %0d", redirect_seen, EXPECTED_REDIRECTS);
        $display("PC transitions checked   : %0d; errors=%0d", pc_step_count, pc_step_errors);
        $display("Load-use stalls          : %0d expected %0d", stall_seen, EXPECTED_LOAD_STALLS);
        $display("EX/MEM store forwarding  : %0d", saw_exmem_store_forward);
        $display("MEM/WB store forwarding  : %0d", saw_memwb_store_forward);
        $display("Wrong-path writes x17/x18: %0d", wrong_path_wb_errors);
        $display("Errors: WB=%0d STORE=%0d BRANCH=%0d REDIRECT=%0d REDIRECT-PC=%0d STALL=%0d REG=%0d MEM=%0d",
                 wb_errors, store_errors, branch_errors, redirect_errors,
                 redirect_pc_errors, stall_errors, reg_errors, mem_errors);
        $display("====================================================");

        if (instruction_errors == 0 &&
            wb_errors == 0 && store_errors == 0 && branch_errors == 0 &&
            redirect_errors == 0 && redirect_pc_errors == 0 &&
            pc_step_errors == 0 && stall_errors == 0 &&
            reg_errors == 0 && mem_errors == 0 &&
            wrong_path_wb_errors == 0 &&
            wb_seen == EXPECTED_WB_EVENTS &&
            store_seen == EXPECTED_STORE_EVENTS &&
            branch_seen == EXPECTED_BRANCHES &&
            taken_branches == 2 && not_taken_branches == 1 &&
            redirect_seen == EXPECTED_REDIRECTS &&
            stall_seen == EXPECTED_LOAD_STALLS &&
            saw_exmem_store_forward && saw_memwb_store_forward) begin
            $display("ALL 15-WORD VERIFICATION CHECKS PASSED");
        end
        else begin
            $display("VERIFICATION FAILED - inspect the first [FAIL ...] line above.");
        end
        $display("====================================================");
        $finish;
    end

    // ------------------------------------------------------------
    // Check the instruction image actually loaded by the DUT
    // ------------------------------------------------------------

    initial begin
        #2;
        $display("");
        $display("========== LOADED 15-WORD PROGRAM ==========");
        for (k = 0; k < PROGRAM_WORDS; k = k + 1) begin
            $display("IMEM[%0d] PC=%0d WORD=%08h EXPECTED=%08h",
                     k, k*4, uut.f2.instr_mem_256[k], expected_instr[k]);
            if (uut.f2.instr_mem_256[k] !== expected_instr[k]) begin
                $display("[FAIL IMEM] index=%0d", k);
                instruction_errors = instruction_errors + 1;
            end
        end
        if (instruction_errors == 0)
            $display("[PASS IMEM] All 15 program words match.");
        $display("==============================================");
    end

    // ------------------------------------------------------------
    // Ordered register-writeback scoreboard
    // ------------------------------------------------------------

    always @(posedge clk) begin
        if (!rst && uut.MEM_WB[135] === 1'b1 && uut.MEM_WB[132:128] != 5'd0) begin
            if (uut.MEM_WB[132:128] == 5'd17 || uut.MEM_WB[132:128] == 5'd18) begin
                wrong_path_wb_errors = wrong_path_wb_errors + 1;
                $display("[FAIL WRONG-PATH WB] rd=x%0d data=%016h",
                         uut.MEM_WB[132:128], uut.which_data);
            end

            if (wb_seen >= EXPECTED_WB_EVENTS) begin
                $display("[FAIL WB] Unexpected extra write rd=x%0d data=%016h",
                         uut.MEM_WB[132:128], uut.which_data);
                wb_errors = wb_errors + 1;
            end
            else if (uut.MEM_WB[132:128] !== expected_wb_rd[wb_seen] ||
                     uut.which_data !== expected_wb_data[wb_seen]) begin
                $display("[FAIL WB #%0d] expected x%0d=%016h; actual x%0d=%016h",
                         wb_seen+1,
                         expected_wb_rd[wb_seen], expected_wb_data[wb_seen],
                         uut.MEM_WB[132:128], uut.which_data);
                wb_errors = wb_errors + 1;
            end
            else begin
                $display("[PASS WB #%0d] x%0d = %016h",
                         wb_seen+1, uut.MEM_WB[132:128], uut.which_data);
            end
            wb_seen = wb_seen + 1;
        end
    end

    // ------------------------------------------------------------
    // Ordered memory-store scoreboard
    // ------------------------------------------------------------

    always @(posedge clk) begin
        if (!rst && uut.f8.write_enable === 1'b1 && uut.f8.read_enable !== 1'b1) begin
            if (store_seen >= EXPECTED_STORE_EVENTS) begin
                $display("[FAIL STORE] Unexpected extra store index=%0d data=%016h",
                         uut.f8.address, uut.f8.write_data);
                store_errors = store_errors + 1;
            end
            else if (uut.f8.address !== expected_store_index[store_seen] ||
                     uut.f8.byte_enable !== 8'hFF ||
                     uut.f8.write_data !== expected_store_data[store_seen]) begin
                $display("[FAIL STORE #%0d] expected index=%0d data=%016h mask=FF; actual index=%0d data=%016h mask=%02h",
                         store_seen+1,
                         expected_store_index[store_seen], expected_store_data[store_seen],
                         uut.f8.address, uut.f8.write_data, uut.f8.byte_enable);
                store_errors = store_errors + 1;
            end
            else begin
                $display("[PASS STORE #%0d] mem[%0d] = %016h mask=%02h",
                         store_seen+1, uut.f8.address, uut.f8.write_data, uut.f8.byte_enable);
            end
            store_seen = store_seen + 1;
        end
    end

    // ------------------------------------------------------------
    // Stall and store-data forwarding coverage
    // ------------------------------------------------------------

    always @(posedge clk) begin
        if (!rst) begin
            if (uut.stall === 1'b1)
                stall_seen = stall_seen + 1;

            if (uut.id_ex_data_mem_write_en === 1'b1) begin
                if (uut.SmuxSel === 3'b010)
                    saw_exmem_store_forward = 1;
                if (uut.SmuxSel === 3'b100)
                    saw_memwb_store_forward = 1;
            end
        end
    end

    // ------------------------------------------------------------
    // Branch execution scoreboard; uses forwarded comparison operands
    // ------------------------------------------------------------

    always @(negedge clk) begin
        if (!rst && uut.ID_EX[266] === 1'b1) begin
            branch_seen = branch_seen + 1;
            b_pc = uut.ID_EX[255:192];
            b_rs1 = uut.regVSimm1;
            b_rs2 = uut.regVSimm2;
            b_target_calc = b_pc + uut.ID_EX[63:0];
            b_pc_known = 1'b1;

            case (b_pc)
                64'd36: begin
                    b_expected_funct3 = 3'b000; // BEQ x1,x1,+8
                    b_expected_rs1 = 64'd5;
                    b_expected_rs2 = 64'd5;
                    b_expected_target = 64'd44;
                    b_expected_taken = 1'b1;
                    taken_branches = taken_branches + 1;
                end
                64'd44: begin
                    b_expected_funct3 = 3'b001; // BNE x1,x1,+8; not taken
                    b_expected_rs1 = 64'd5;
                    b_expected_rs2 = 64'd5;
                    b_expected_target = 64'd52;
                    b_expected_taken = 1'b0;
                    not_taken_branches = not_taken_branches + 1;
                end
                64'd48: begin
                    b_expected_funct3 = 3'b001; // BNE x1,x2,+8
                    b_expected_rs1 = 64'd5;
                    b_expected_rs2 = 64'd7;
                    b_expected_target = 64'd56;
                    b_expected_taken = 1'b1;
                    taken_branches = taken_branches + 1;
                end
                default: begin
                    b_pc_known = 1'b0;
                    branch_errors = branch_errors + 1;
                    $display("[FAIL BRANCH] Unexpected branch PC=%0d", b_pc);
                end
            endcase

            $display("[BRANCH] PC=%0d operands=(%016h,%016h) funct3=%b actual_taken=%b target=%0d",
                     b_pc, b_rs1, b_rs2, uut.ID_EX[258:256],
                     uut.branch_cond_ok, b_target_calc);

            if (b_pc_known) begin
                if (uut.ID_EX[258:256] !== b_expected_funct3 ||
                    b_rs1 !== b_expected_rs1 || b_rs2 !== b_expected_rs2 ||
                    b_target_calc !== b_expected_target ||
                    uut.branch_cond_ok !== b_expected_taken ||
                    uut.pc_mux_control !== b_expected_taken) begin
                    branch_errors = branch_errors + 1;
                    $display("[FAIL BRANCH] PC=%0d expected operands=(%016h,%016h) funct3=%b taken=%b target=%0d",
                             b_pc, b_expected_rs1, b_expected_rs2,
                             b_expected_funct3, b_expected_taken, b_expected_target);
                end
                else begin
                    $display("[PASS BRANCH] PC=%0d taken=%b target=%0d",
                             b_pc, b_expected_taken, b_expected_target);
                end
            end
        end
    end

    // ------------------------------------------------------------
    // Redirect scoreboard and next-edge PC target check
    // ------------------------------------------------------------

    always @(negedge clk) begin
        if (!rst && uut.EX_MEM[132] === 1'b1) begin
            redirect_seen = redirect_seen + 1;

            if (redirect_seen == 1)
                redirect_expected_target = 64'd44;
            else if (redirect_seen == 2)
                redirect_expected_target = 64'd56;
            else begin
                redirect_expected_target = uut.EX_MEM[131:68];
                redirect_errors = redirect_errors + 1;
                $display("[FAIL REDIRECT] Unexpected redirect #%0d", redirect_seen);
            end

            $display("[REDIRECT] #%0d target=%0d current_PC=%0d",
                     redirect_seen, uut.EX_MEM[131:68], uut.pcounter);

            if (redirect_seen <= EXPECTED_REDIRECTS) begin
                if (uut.EX_MEM[131:68] !== redirect_expected_target) begin
                    redirect_errors = redirect_errors + 1;
                    $display("[FAIL REDIRECT] expected target=%0d actual=%0d",
                             redirect_expected_target, uut.EX_MEM[131:68]);
                end
                else begin
                    $display("[PASS REDIRECT] target=%0d", redirect_expected_target);
                end
            end

            pending_target = uut.EX_MEM[131:68];
            redirect_pending = 1'b1;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            redirect_pending = 1'b0;
        end
        else if (redirect_pending) begin
            #1;
            if (uut.pcounter !== pending_target) begin
                redirect_pc_errors = redirect_pc_errors + 1;
                $display("[FAIL REDIRECT PC] expected=%0d actual=%0d",
                         pending_target, uut.pcounter);
            end
            else begin
                $display("[PASS REDIRECT PC] PC reached %0d", pending_target);
            end
            redirect_pending = 1'b0;
        end
    end

    // ------------------------------------------------------------
    // PC-transition checker: reset > redirect > stall > PC+4
    // ------------------------------------------------------------

    always @(posedge clk) begin
        if (rst) begin
            #1;
            if (uut.pcounter !== 64'd0) begin
                pc_step_errors = pc_step_errors + 1;
                $display("[FAIL PC] Reset should set PC=0; actual=%0d", uut.pcounter);
            end
        end
        else begin
            pc_before = uut.pcounter;
            if (uut.EX_MEM[132] === 1'b1)
                pc_expected_next = uut.EX_MEM[131:68];
            else if (uut.stall === 1'b1)
                pc_expected_next = pc_before;
            else
                pc_expected_next = pc_before + 64'd4;

            #1;
            pc_step_count = pc_step_count + 1;
            if (uut.pcounter !== pc_expected_next) begin
                pc_step_errors = pc_step_errors + 1;
                $display("[FAIL PC] expected next=%0d actual=%0d before=%0d redirect=%b stall=%b",
                         pc_expected_next, uut.pcounter, pc_before,
                         uut.EX_MEM[132], uut.stall);
            end
        end
    end

    // ------------------------------------------------------------
    // Watchdog
    // ------------------------------------------------------------

    initial begin
        #20000;
        $display("[FATAL] Watchdog timeout; possible control-flow hang.");
        $finish;
    end

endmodule
