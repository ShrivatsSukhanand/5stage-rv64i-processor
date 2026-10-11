`timescale 1ns / 1ps

module tb_core;

    parameter [31:0] TEST_SEED = 32'h51A7C0DE;

    reg clk;
    reg rst;

    wire ex_mem_N;
    wire ex_mem_Z;
    wire ex_mem_C;
    wire ex_mem_V;

    localparam integer TEST_CYCLES = 160;
    localparam integer INPUT_COUNT = 8;
    localparam integer DMEM_WORDS = 512;
    localparam integer EXPECTED_BRANCHES = 11;
    localparam integer EXPECTED_REDIRECTS = 9;
    localparam integer EXPECTED_STALLS = 9;
    localparam integer EXPECTED_STORES = 26;

    integer i;
    integer k;
    integer loop_branch_seen;
    integer branch_seen;
    integer branch_errors;
    integer redirect_seen;
    integer redirect_errors;
    integer redirect_pc_errors;
    integer pc_step_errors;
    integer pc_step_count;
    integer stall_seen;
    integer wb_seen;
    integer wb_errors;
    integer store_seen;
    integer store_errors;
    integer reg_errors;
    integer mem_errors;
    integer stall_errors;
    integer unexpected_x17_wb;
    integer saw_exmem_store_forward;
    integer saw_memwb_store_forward;

    integer expected_wb_count;
    integer expected_store_count;

    reg [31:0] seed;
    reg [31:0] rng_word_hi;
    reg [31:0] rng_word_lo;

    reg [63:0] random_input [0:INPUT_COUNT-1];
    reg [63:0] expected_prefix [0:INPUT_COUNT-1];
    reg [63:0] expected_mem [0:DMEM_WORDS-1];
    reg [63:0] expected_reg [0:31];

    reg [4:0]  expected_wb_rd [0:95];
    reg [63:0] expected_wb_data [0:95];

    reg [63:0] expected_store_addr [0:31];
    reg [63:0] expected_store_data [0:31];

    reg [63:0] model_sum;
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

    // Reproducible pseudo-random data generator; seed is printed in the log.
    function [31:0] xorshift32;
        input [31:0] input_value;
        reg [31:0] x;
        begin
            x = input_value;
            x = x ^ (x << 13);
            x = x ^ (x >> 17);
            x = x ^ (x << 5);
            xorshift32 = x;
        end
    endfunction

    // Build the expected architectural writeback stream in program order.
    task push_expected_wb;
        input [4:0] rd_value;
        input [63:0] data_value;
        begin
            if (expected_wb_count < 96) begin
                expected_wb_rd[expected_wb_count] = rd_value;
                expected_wb_data[expected_wb_count] = data_value;
                expected_wb_count = expected_wb_count + 1;
            end
            else begin
                $display("[TB SETUP ERROR] Expected-WB array overflow");
                wb_errors = wb_errors + 1;
            end
        end
    endtask

    // Build the expected sequence of actual doubleword store transactions.
    task push_expected_store;
        input [63:0] address_index;
        input [63:0] data_value;
        begin
            if (expected_store_count < 32) begin
                expected_store_addr[expected_store_count] = address_index;
                expected_store_data[expected_store_count] = data_value;
                expected_store_count = expected_store_count + 1;
            end
            else begin
                $display("[TB SETUP ERROR] Expected-store array overflow");
                store_errors = store_errors + 1;
            end
        end
    endtask

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
    // Randomized input initialization + independent reference model
    // ------------------------------------------------------------

    initial begin
        clk = 1'b0;
        rst = 1'b1;

        branch_seen = 0;
        loop_branch_seen = 0;
        branch_errors = 0;
        redirect_seen = 0;
        redirect_errors = 0;
        redirect_pc_errors = 0;
        pc_step_errors = 0;
        pc_step_count = 0;
        stall_seen = 0;
        wb_seen = 0;
        wb_errors = 0;
        store_seen = 0;
        store_errors = 0;
        reg_errors = 0;
        mem_errors = 0;
        stall_errors = 0;
        unexpected_x17_wb = 0;
        saw_exmem_store_forward = 0;
        saw_memwb_store_forward = 0;
        expected_wb_count = 0;
        expected_store_count = 0;
        redirect_pending = 1'b0;
        pending_target = 64'd0;
        model_sum = 64'd0;
        b_pc_known = 1'b0;

        $dumpfile("tb_core_prefix_sum.vcd");
        $dumpvars(0, tb_core);

        // Allow the DUT's $readmemb initialization to finish before seeding RAM.
        #1;
        seed = TEST_SEED;

        // Define all RAM locations. This makes the test independent of data_list.txt.
        for (i = 0; i < DMEM_WORDS; i = i + 1) begin
            uut.f8.mem[i] = 64'd0;
            expected_mem[i] = 64'd0;
        end

        // Deterministic random 64-bit inputs at data-memory words 0..7.
        for (i = 0; i < INPUT_COUNT; i = i + 1) begin
            seed = xorshift32(seed);
            rng_word_hi = seed;
            seed = xorshift32(seed);
            rng_word_lo = seed;
            random_input[i] = {rng_word_hi, rng_word_lo};
            uut.f8.mem[i] = random_input[i];
            expected_mem[i] = random_input[i];
        end

        $display("====================================================");
        $display(" RV64I SEEDED PREFIX-SUM / PIPELINE STRESS TEST");
        $display(" Seed: 0x%08h; instructions: ADDI, LD, ADD, SD, SLLI, BEQ, BNE", TEST_SEED);
        $display("====================================================");
        for (i = 0; i < INPUT_COUNT; i = i + 1)
            $display("INPUT mem[%0d] = %016h", i, random_input[i]);

        // Expected register writes from the six setup ADDIs.
        push_expected_wb(5'd10, 64'd0);
        push_expected_wb(5'd11, 64'd8);
        push_expected_wb(5'd12, 64'd64);
        push_expected_wb(5'd19, 64'd128);
        push_expected_wb(5'd21, 64'd192);
        push_expected_wb(5'd13, 64'd0);

        // Independent software model: prefix sum + mirrored prefix + input*2.
        model_sum = 64'd0;
        for (i = 0; i < INPUT_COUNT; i = i + 1) begin
            model_sum = model_sum + random_input[i];
            expected_prefix[i] = model_sum;

            expected_mem[8+i]  = model_sum;
            expected_mem[16+i] = model_sum;
            expected_mem[24+i] = random_input[i] << 1;

            // Register-write order in one loop iteration.
            push_expected_wb(5'd14, random_input[i]);
            push_expected_wb(5'd13, model_sum);
            push_expected_wb(5'd20, random_input[i] << 1);
            push_expected_wb(5'd10, (i+1) * 8);
            push_expected_wb(5'd12, 64 + (i+1) * 8);
            push_expected_wb(5'd19, 128 + (i+1) * 8);
            push_expected_wb(5'd21, 192 + (i+1) * 8);
            push_expected_wb(5'd11, 7-i);

            // Store order in one loop iteration: prefix, mirror, shifted input.
            push_expected_store(64'd8 + i, model_sum);
            push_expected_store(64'd16 + i, model_sum);
            push_expected_store(64'd24 + i, random_input[i] << 1);
        end

        // Epilogue: final sum, verify it against the last prefix, marker store.
        expected_mem[32] = model_sum;
        expected_mem[33] = 64'd123;
        push_expected_store(64'd32, model_sum);
        push_expected_store(64'd33, 64'd123);
        push_expected_wb(5'd15, model_sum);
        push_expected_wb(5'd16, 64'd123);

        for (i = 0; i < 32; i = i + 1)
            expected_reg[i] = 64'd0;
        expected_reg[10] = 64'd64;
        expected_reg[11] = 64'd0;
        expected_reg[12] = 64'd128;
        expected_reg[13] = model_sum;
        expected_reg[14] = random_input[INPUT_COUNT-1];
        expected_reg[15] = model_sum;
        expected_reg[16] = 64'd123;
        expected_reg[19] = 64'd192;
        expected_reg[20] = random_input[INPUT_COUNT-1] << 1;
        expected_reg[21] = 64'd256;

        $display("Expected final sum = %016h", model_sum);
        $display("Expected WB events = %0d; expected stores = %0d",
                 expected_wb_count, expected_store_count);

        // Reset for two rising edges, then release on a falling edge.
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
        for (i = 0; i < 32; i = i + 1)
            check_reg(i, expected_reg[i]);

        // --------------------------------------------------------
        // Final check of every RAM word
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
        // Coverage and event-count assertions
        // --------------------------------------------------------
        $display("");
        $display("========== PIPELINE / CONTROL ASSERTIONS ==========");
        if (wb_seen != expected_wb_count) begin
            $display("[FAIL] Writeback event count mismatch.");
            wb_errors = wb_errors + 1;
        end
        if (store_seen != expected_store_count || store_seen != EXPECTED_STORES) begin
            $display("[FAIL] Store event count mismatch.");
            store_errors = store_errors + 1;
        end
        if (branch_seen != EXPECTED_BRANCHES || loop_branch_seen != 8) begin
            $display("[FAIL] Branch execution count mismatch.");
            branch_errors = branch_errors + 1;
        end
        if (redirect_seen != EXPECTED_REDIRECTS) begin
            $display("[FAIL] Redirect count mismatch.");
            redirect_errors = redirect_errors + 1;
        end
        if (stall_seen != EXPECTED_STALLS) begin
            $display("[FAIL] Load-use stall count mismatch.");
            stall_errors = stall_errors + 1;
        end
        if (!saw_exmem_store_forward) begin
            $display("[FAIL] EX/MEM store-data forwarding was not observed.");
            store_errors = store_errors + 1;
        end
        if (!saw_memwb_store_forward) begin
            $display("[FAIL] MEM/WB store-data forwarding was not observed.");
            store_errors = store_errors + 1;
        end
        if (unexpected_x17_wb != 0) begin
            $display("[FAIL] Failure/wrong-path instruction wrote x17.");
            wb_errors = wb_errors + 1;
        end

        $display("WB events: %0d expected %0d", wb_seen, expected_wb_count);
        $display("Store events: %0d expected %0d", store_seen, expected_store_count);
        $display("Branches: %0d expected %0d", branch_seen, EXPECTED_BRANCHES);
        $display("Loop BNE executions: %0d expected 8", loop_branch_seen);
        $display("Redirects: %0d expected %0d", redirect_seen, EXPECTED_REDIRECTS);
        $display("PC transitions checked: %0d; PC transition errors: %0d", pc_step_count, pc_step_errors);
        $display("Load-use stall cycles: %0d expected %0d", stall_seen, EXPECTED_STALLS);
        $display("EX/MEM store forwarding observed: %0d", saw_exmem_store_forward);
        $display("MEM/WB store forwarding observed: %0d", saw_memwb_store_forward);
        $display("Unexpected x17 writebacks: %0d", unexpected_x17_wb);
        $display("WB errors=%0d STORE errors=%0d BRANCH errors=%0d REDIRECT errors=%0d REDIRECT-PC errors=%0d PC-step errors=%0d STALL errors=%0d REG errors=%0d MEM errors=%0d",
                 wb_errors, store_errors, branch_errors, redirect_errors,
                 redirect_pc_errors, pc_step_errors, stall_errors, reg_errors, mem_errors);

        $display("====================================================");
        if (wb_errors == 0 && store_errors == 0 && branch_errors == 0 &&
            redirect_errors == 0 && redirect_pc_errors == 0 && pc_step_errors == 0 && stall_errors == 0 &&
            reg_errors == 0 && mem_errors == 0 &&
            wb_seen == expected_wb_count && store_seen == expected_store_count &&
            branch_seen == EXPECTED_BRANCHES && loop_branch_seen == 8 &&
            redirect_seen == EXPECTED_REDIRECTS && stall_seen == EXPECTED_STALLS &&
            saw_exmem_store_forward && saw_memwb_store_forward &&
            unexpected_x17_wb == 0) begin
            $display("ALL SEEDED PREFIX-SUM REGRESSION CHECKS PASSED");
        end
        else begin
            $display("REGRESSION FAILED — inspect the first [FAIL] line above.");
        end
        $display("====================================================");
        $finish;
    end

    // ------------------------------------------------------------
    // Writeback scoreboard: compares every non-x0 architectural write
    // against an independently generated ordered reference stream.
    // ------------------------------------------------------------

    always @(posedge clk) begin
        if (!rst && uut.MEM_WB[135] === 1'b1 && uut.MEM_WB[132:128] != 5'd0) begin
            if (uut.MEM_WB[132:128] == 5'd17)
                unexpected_x17_wb = unexpected_x17_wb + 1;

            if (wb_seen >= expected_wb_count) begin
                $display("[FAIL WB] Unexpected extra write rd=x%0d data=%016h",
                         uut.MEM_WB[132:128], uut.which_data);
                wb_errors = wb_errors + 1;
            end
            else if (uut.MEM_WB[132:128] !== expected_wb_rd[wb_seen] ||
                     uut.which_data !== expected_wb_data[wb_seen]) begin
                $display("[FAIL WB #%0d] expected x%0d=%016h; actual x%0d=%016h",
                         wb_seen,
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
    // Store scoreboard: every store address/data/mask checked at write edge
    // ------------------------------------------------------------

    always @(posedge clk) begin
        if (!rst && uut.f8.write_enable === 1'b1 && uut.f8.read_enable !== 1'b1) begin
            if (store_seen >= expected_store_count) begin
                $display("[FAIL STORE] Unexpected extra store: index=%0d data=%016h",
                         uut.f8.address, uut.f8.write_data);
                store_errors = store_errors + 1;
            end
            else if (uut.f8.address !== expected_store_addr[store_seen] ||
                     uut.f8.byte_enable !== 8'hFF ||
                     uut.f8.write_data !== expected_store_data[store_seen]) begin
                $display("[FAIL STORE #%0d] expected index=%0d data=%016h mask=FF; actual index=%0d data=%016h mask=%02h",
                         store_seen,
                         expected_store_addr[store_seen], expected_store_data[store_seen],
                         uut.f8.address, uut.f8.write_data, uut.f8.byte_enable);
                store_errors = store_errors + 1;
            end
            else begin
                $display("[PASS STORE #%0d] mem[%0d] = %016h",
                         store_seen+1, uut.f8.address, uut.f8.write_data);
            end
            store_seen = store_seen + 1;
        end
    end

    // ------------------------------------------------------------
    // Stall and store-data forwarding coverage monitors
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
    // PC sequencer scoreboard: check every clock transition.
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
            if (uut.ex_mem_pc_mux_control === 1'b1)
                pc_expected_next = uut.ex_mem_new_pc;
            else if (uut.stall === 1'b1)
                pc_expected_next = pc_before;
            else
                pc_expected_next = pc_before + 64'd4;

            #1;
            pc_step_count = pc_step_count + 1;
            if (uut.pcounter !== pc_expected_next) begin
                pc_step_errors = pc_step_errors + 1;
                $display("[FAIL PC] expected next PC=%0d actual=%0d (before=%0d redirect=%b stall=%b)",
                         pc_expected_next, uut.pcounter, pc_before,
                         uut.ex_mem_pc_mux_control, uut.stall);
            end
        end
    end

    // ------------------------------------------------------------
    // Branch execution scoreboard; observes forwarded compare operands.
    // PC decimal locations come from the assembled program below.
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
                64'd68: begin
                    loop_branch_seen = loop_branch_seen + 1;
                    b_expected_funct3 = 3'b001; // BNE x11,x0,loop
                    b_expected_rs1 = 64'd8 - loop_branch_seen;
                    b_expected_rs2 = 64'd0;
                    b_expected_target = 64'd24;
                    b_expected_taken = (loop_branch_seen < 8);
                    if (loop_branch_seen > 8) begin
                        branch_errors = branch_errors + 1;
                        $display("[FAIL BRANCH] Loop branch executed more than 8 times.");
                    end
                end

                64'd80: begin
                    b_expected_funct3 = 3'b001; // BNE x13,x15,fail
                    b_expected_rs1 = model_sum;
                    b_expected_rs2 = model_sum;
                    b_expected_target = 64'd104;
                    b_expected_taken = 1'b0;
                end

                64'd88: begin
                    b_expected_funct3 = 3'b000; // BEQ x13,x15,store_marker
                    b_expected_rs1 = model_sum;
                    b_expected_rs2 = model_sum;
                    b_expected_target = 64'd96;
                    b_expected_taken = 1'b1;
                end

                64'd100: begin
                    b_expected_funct3 = 3'b000; // BEQ x0,x0,done
                    b_expected_rs1 = 64'd0;
                    b_expected_rs2 = 64'd0;
                    b_expected_target = 64'd108;
                    b_expected_taken = 1'b1;
                end

                default: begin
                    b_pc_known = 1'b0;
                    branch_errors = branch_errors + 1;
                    $display("[FAIL BRANCH] Unexpected branch PC=%0d", b_pc);
                end
            endcase

            $display("[BRANCH] PC=%0d rs1=%016h rs2=%016h funct3=%b cond=%b redirect=%b target=%0d",
                     b_pc, b_rs1, b_rs2, uut.ID_EX[258:256],
                     uut.branch_cond_ok, uut.pc_mux_control, b_target_calc);

            if (b_pc_known) begin
                if (uut.ID_EX[258:256] !== b_expected_funct3 ||
                    b_rs1 !== b_expected_rs1 ||
                    b_rs2 !== b_expected_rs2 ||
                    b_target_calc !== b_expected_target ||
                    uut.branch_cond_ok !== b_expected_taken ||
                    uut.pc_mux_control !== b_expected_taken) begin
                    branch_errors = branch_errors + 1;
                    $display("[FAIL BRANCH] PC=%0d expected rs1=%016h rs2=%016h funct3=%b taken=%b target=%0d",
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
    // Redirect scoreboard: 7 loop-back redirects, then 96 and 108.
    // ------------------------------------------------------------

    always @(negedge clk) begin
        if (!rst && uut.EX_MEM[132] === 1'b1) begin
            redirect_seen = redirect_seen + 1;

            if (redirect_seen <= 7)
                redirect_expected_target = 64'd24;
            else if (redirect_seen == 8)
                redirect_expected_target = 64'd96;
            else if (redirect_seen == 9)
                redirect_expected_target = 64'd108;
            else begin
                redirect_expected_target = uut.EX_MEM[131:68];
                redirect_errors = redirect_errors + 1;
                $display("[FAIL REDIRECT] Unexpected redirect #%0d", redirect_seen);
            end

            $display("[REDIRECT] #%0d target=%0d current_PC=%0d",
                     redirect_seen, uut.EX_MEM[131:68], uut.pcounter);

            if (redirect_seen <= EXPECTED_REDIRECTS &&
                uut.EX_MEM[131:68] !== redirect_expected_target) begin
                redirect_errors = redirect_errors + 1;
                $display("[FAIL REDIRECT] expected target=%0d actual=%0d",
                         redirect_expected_target, uut.EX_MEM[131:68]);
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
    // Instruction-memory dump: proves the simulator loaded the expected image.
    // ------------------------------------------------------------

    initial begin
        #2;
        $display("========== LOADED PROGRAM (first 28 words) ==========");
        for (k = 0; k < 28; k = k + 1)
            $display("IMEM[%0d] @ PC %0d = %08h",
                     k, k*4, uut.f2.instr_mem_256[k]);
        $display("=====================================================");
    end

    // ------------------------------------------------------------
    // Watchdog
    // ------------------------------------------------------------

    initial begin
        #100000;
        $display("[FATAL] Watchdog timeout; likely stuck control flow.");
        $finish;
    end

endmodule
