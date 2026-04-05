`timescale 1ns/1ps

module riscv_tb_24112083;

    reg         clk;
    reg         reset;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [3:0]  mem_wmask;
    wire [31:0] mem_rdata;
    wire        mem_rstrb;
    reg         mem_rbusy;
    reg         mem_wbusy;

    reg [31:0] memory [0:4095];
    reg [31:0] read_data;

    integer test_num;
    integer passed_tests;
    integer total_tests;
    integer cycle_count;
    integer i;

    riscv_processor uut (
        .clk(clk),
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .mem_wmask(mem_wmask),
        .mem_rdata(mem_rdata),
        .mem_rstrb(mem_rstrb),
        .mem_rbusy(mem_rbusy),
        .mem_wbusy(mem_wbusy),
        .reset(reset)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    always @(posedge clk) begin
        if (mem_rstrb) begin
            read_data <= memory[mem_addr[31:2]];
        end
    end

    assign mem_rdata = read_data;

    always @(posedge clk) begin
        if (mem_wmask != 4'b0000) begin
            if (mem_wmask[0]) memory[mem_addr[31:2]][7:0]   <= mem_wdata[7:0];
            if (mem_wmask[1]) memory[mem_addr[31:2]][15:8]  <= mem_wdata[15:8];
            if (mem_wmask[2]) memory[mem_addr[31:2]][23:16] <= mem_wdata[23:16];
            if (mem_wmask[3]) memory[mem_addr[31:2]][31:24] <= mem_wdata[31:24];
        end
    end

    initial begin
        mem_rbusy = 0;
        mem_wbusy = 0;
    end

    always @(posedge clk) begin
        if (!reset)
            cycle_count <= 0;
        else
            cycle_count <= cycle_count + 1;
    end

    task init_memory;
        begin
            for (i = 0; i < 4096; i = i + 1) begin
                memory[i] = 32'h00000013;
            end
            read_data = 32'h00000013;
        end
    endtask

    task reset_processor;
        begin
            reset = 0;
            @(posedge clk);
            @(posedge clk);
            reset = 1;
            cycle_count = 0;
        end
    endtask

    task wait_for_pc;
        input [31:0] target_pc;
        input integer max_cycles;
        integer j;
        begin
            for (j = 0; j < max_cycles; j = j + 1) begin
                @(posedge clk);
                if (mem_addr == target_pc && mem_rstrb) begin
                    j = max_cycles;
                end
            end
        end
    endtask

    task check_result;
        input [31:0] addr;
        input [31:0] expected;
        input [200*8:1] test_name;
        begin
            total_tests = total_tests + 1;
            if (memory[addr[31:2]] === expected) begin
                $display("[PASS] Test %0d: %s", test_num, test_name);
                $display("       Expected: 0x%08h, Got: 0x%08h", expected, memory[addr[31:2]]);
                passed_tests = passed_tests + 1;
            end else begin
                $display("[FAIL] Test %0d: %s", test_num, test_name);
                $display("       Expected: 0x%08h, Got: 0x%08h", expected, memory[addr[31:2]]);
            end
        end
    endtask

    task test_add_sub;
        begin
            test_num = 1;
            $display("\n========================================");
            $display("Test 1: ADD and SUB");
            $display("========================================");

            init_memory();

            memory[0] = 32'h00C00093;
            memory[1] = 32'h00700113;
            memory[2] = 32'h002081B3;
            memory[3] = 32'h40208233;
            memory[4] = 32'h00302023;
            memory[5] = 32'h00402223;
            memory[6] = 32'h0180006F;

            reset_processor();
            wait_for_pc(32'd24, 400);

            check_result(32'h00000000, 32'h00000013, "ADD 12+7=19");
            check_result(32'h00000004, 32'h00000005, "SUB 12-7=5");
        end
    endtask

    task test_xor_or_and;
        begin
            test_num = 2;
            $display("\n========================================");
            $display("Test 2: XOR OR AND");
            $display("========================================");

            init_memory();

            memory[0] = 32'h0A500093;
            memory[1] = 32'h05A00113;
            memory[2] = 32'h0020C1B3;
            memory[3] = 32'h0020E233;
            memory[4] = 32'h0020F2B3;
            memory[5] = 32'h00302023;
            memory[6] = 32'h00402223;
            memory[7] = 32'h00502423;
            memory[8] = 32'h0200006F;

            reset_processor();
            wait_for_pc(32'd32, 400);

            check_result(32'h00000000, 32'h000000FF, "XOR 0xA5^0x5A=0xFF");
            check_result(32'h00000004, 32'h000000FF, "OR  0xA5|0x5A=0xFF");
            check_result(32'h00000008, 32'h00000000, "AND 0xA5&0x5A=0x00");
        end
    endtask

    task test_sll_srl_sra;
        begin
            test_num = 3;
            $display("\n========================================");
            $display("Test 3: SLL SRL SRA");
            $display("========================================");

            init_memory();

            memory[0] = 32'h00100093;
            memory[1] = 32'h00400113;
            memory[2] = 32'h002091B3;
            memory[3] = 32'h80000237;
            memory[4] = 32'h002252B3;
            memory[5] = 32'h40225333;
            memory[6] = 32'h00302023;
            memory[7] = 32'h00502223;
            memory[8] = 32'h00602423;
            memory[9] = 32'h0240006F;

            reset_processor();
            wait_for_pc(32'd36, 400);

            check_result(32'h00000000, 32'h00000010, "SLL 1<<4=16");
            check_result(32'h00000004, 32'h08000000, "SRL 0x80000000>>4");
            check_result(32'h00000008, 32'hF8000000, "SRA 0x80000000>>4 (sign ext)");
        end
    endtask

    task test_slt_sltu;
        begin
            test_num = 4;
            $display("\n========================================");
            $display("Test 4: SLT and SLTU");
            $display("========================================");

            init_memory();

            memory[0] = 32'hFFF00093;
            memory[1] = 32'h00300113;
            memory[2] = 32'h0020A1B3;
            memory[3] = 32'h0020B233;
            memory[4] = 32'h00302023;
            memory[5] = 32'h00402223;
            memory[6] = 32'h0180006F;

            reset_processor();
            wait_for_pc(32'd24, 400);

            check_result(32'h00000000, 32'h00000001, "SLT signed: -1<3=1");
            check_result(32'h00000004, 32'h00000000, "SLTU unsigned: 0xFFFFFFFF<3=0");
        end
    endtask

    task test_addi_xori_ori_andi;
        begin
            test_num = 5;
            $display("\n========================================");
            $display("Test 5: ADDI XORI ORI ANDI");
            $display("========================================");

            init_memory();

            memory[0] = 32'h03300093;
            memory[1] = 32'h06408113;
            memory[2] = 32'h0CC0C193;
            memory[3] = 32'h0F00E213;
            memory[4] = 32'h00F0F293;
            memory[5] = 32'h00202023;
            memory[6] = 32'h00302223;
            memory[7] = 32'h00402423;
            memory[8] = 32'h00502623;
            memory[9] = 32'h0280006F;

            reset_processor();
            wait_for_pc(32'd40, 400);

            check_result(32'h00000000, 32'h00000097, "ADDI 0x33+0x64=0x97");
            check_result(32'h00000004, 32'h000000FF, "XORI 0x33^0xCC=0xFF");
            check_result(32'h00000008, 32'h000000F3, "ORI  0x33|0xF0=0xF3");
            check_result(32'h0000000C, 32'h00000003, "ANDI 0x33&0x0F=0x03");
        end
    endtask

    task test_slli_srli_srai;
        begin
            test_num = 6;
            $display("\n========================================");
            $display("Test 6: SLLI SRLI SRAI");
            $display("========================================");

            init_memory();

            memory[0] = 32'h800000B7;
            memory[1] = 32'h04008093;
            memory[2] = 32'h00209113;
            memory[3] = 32'h0020D193;
            memory[4] = 32'h4020D213;
            memory[5] = 32'h00202023;
            memory[6] = 32'h00302223;
            memory[7] = 32'h00402423;
            memory[8] = 32'h0240006F;

            reset_processor();
            wait_for_pc(32'd36, 400);

            check_result(32'h00000000, 32'h00000100, "SLLI 0x80000040<<2=0x100");
            check_result(32'h00000004, 32'h20000010, "SRLI 0x80000040>>2=0x20000010");
            check_result(32'h00000008, 32'hE0000010, "SRAI 0x80000040>>2=0xE0000010");
        end
    endtask

    task test_slti_sltiu;
        begin
            test_num = 7;
            $display("\n========================================");
            $display("Test 7: SLTI and SLTIU");
            $display("========================================");

            init_memory();

            memory[0] = 32'h00700093;
            memory[1] = 32'h0140A113;
            memory[2] = 32'h0030A193;
            memory[3] = 32'h0140B213;
            memory[4] = 32'h00202023;
            memory[5] = 32'h00302223;
            memory[6] = 32'h00402423;
            memory[7] = 32'h0200006F;

            reset_processor();
            wait_for_pc(32'd32, 400);

            check_result(32'h00000000, 32'h00000001, "SLTI 7<20=1");
            check_result(32'h00000004, 32'h00000000, "SLTI 7<3=0");
            check_result(32'h00000008, 32'h00000001, "SLTIU 7<20=1");
        end
    endtask

    task test_lb_lh_lw;
        begin
            test_num = 8;
            $display("\n========================================");
            $display("Test 8: LB LH LW");
            $display("========================================");

            init_memory();
            memory[256] = 32'hDEAD8070;

            memory[0] = 32'h40000093;
            memory[1] = 32'h0000A103;
            memory[2] = 32'h00009183;
            memory[3] = 32'h00008203;
            memory[4] = 32'h00202023;
            memory[5] = 32'h00302223;
            memory[6] = 32'h00402423;
            memory[7] = 32'h0200006F;

            reset_processor();
            wait_for_pc(32'd32, 400);

            check_result(32'h00000000, 32'hDEAD8070, "LW full word");
            check_result(32'h00000004, 32'hFFFF8070, "LH sign-extends 0x8070");
            check_result(32'h00000008, 32'h00000070, "LB sign-extends 0x70 (positive)");
        end
    endtask

    task test_lbu_lhu;
        begin
            test_num = 9;
            $display("\n========================================");
            $display("Test 9: LBU and LHU");
            $display("========================================");

            init_memory();
            memory[256] = 32'hDEAD8070;

            memory[0] = 32'h40000093;
            memory[1] = 32'h0000C103;
            memory[2] = 32'h0000D183;
            memory[3] = 32'h00202023;
            memory[4] = 32'h00302223;
            memory[5] = 32'h0140006F;

            reset_processor();
            wait_for_pc(32'd20, 400);

            check_result(32'h00000000, 32'h00000070, "LBU zero-extends 0x70");
            check_result(32'h00000004, 32'h00008070, "LHU zero-extends 0x8070");
        end
    endtask

    task test_sb_sh_sw;
        begin
            test_num = 10;
            $display("\n========================================");
            $display("Test 10: SB SH SW");
            $display("========================================");

            init_memory();

            memory[0] = 32'h50000093;
            memory[1] = 32'h0CD00113;
            memory[2] = 32'h7EF00193;
            memory[3] = 32'h00208023;
            memory[4] = 32'h00309123;
            memory[5] = 32'h0000A203;
            memory[6] = 32'h00402023;
            memory[7] = 32'h01C0006F;

            reset_processor();
            wait_for_pc(32'd28, 400);

            check_result(32'h00000000, 32'h07EF00CD, "SB byte0=0xCD SH half[2]=0x07EF → 0x07EF00CD");
        end
    endtask

    task test_beq;
        begin
            test_num = 11;
            $display("\n========================================");
            $display("Test 11: BEQ taken and not taken");
            $display("========================================");

            init_memory();

            memory[0] = 32'h00900093;
            memory[1] = 32'h00900113;
            memory[2] = 32'h00400193;
            memory[3] = 32'h00208663;
            memory[4] = 32'h06300213;
            memory[5] = 32'h00000013;
            memory[6] = 32'h00100213;
            memory[7] = 32'h00308663;
            memory[8] = 32'h00200293;
            memory[9] = 32'h00C0006F;
            memory[10] = 32'h00000013;
            memory[11] = 32'h00000013;
            memory[12] = 32'h00402023;
            memory[13] = 32'h00502223;
            memory[14] = 32'h0140006F;

            reset_processor();
            wait_for_pc(32'd68, 400);

            check_result(32'h00000000, 32'h00000001, "BEQ taken: 9==9 skip 99 x4=1");
            check_result(32'h00000004, 32'h00000002, "BEQ not taken: 9!=4 x5=2");
        end
    endtask

    task test_bne;
        begin
            test_num = 12;
            $display("\n========================================");
            $display("Test 12: BNE taken and not taken");
            $display("========================================");

            init_memory();

            memory[0] = 32'h00300093;
            memory[1] = 32'h00700113;
            memory[2] = 32'h00300193;
            memory[3] = 32'h00209663;
            memory[4] = 32'h06300213;
            memory[5] = 32'h00000013;
            memory[6] = 32'h00100213;
            memory[7] = 32'h00309663;
            memory[8] = 32'h00200293;
            memory[9] = 32'h00C0006F;
            memory[10] = 32'h00000013;
            memory[11] = 32'h00000013;
            memory[12] = 32'h00402023;
            memory[13] = 32'h00502223;
            memory[14] = 32'h0140006F;

            reset_processor();
            wait_for_pc(32'd68, 400);

            check_result(32'h00000000, 32'h00000001, "BNE taken: 3!=7 x4=1");
            check_result(32'h00000004, 32'h00000002, "BNE not taken: 3==3 x5=2");
        end
    endtask

    task test_blt;
        begin
            test_num = 13;
            $display("\n========================================");
            $display("Test 13: BLT signed taken and not taken");
            $display("========================================");

            init_memory();

            memory[0] = 32'hFFE00093;
            memory[1] = 32'h00500113;
            memory[2] = 32'h0020C663;
            memory[3] = 32'h06300193;
            memory[4] = 32'h00000013;
            memory[5] = 32'h00100193;
            memory[6] = 32'h00114663;
            memory[7] = 32'h00200213;
            memory[8] = 32'h00C0006F;
            memory[9] = 32'h00000013;
            memory[10] = 32'h00000013;
            memory[11] = 32'h00302023;
            memory[12] = 32'h00402223;
            memory[13] = 32'h0140006F;

            reset_processor();
            wait_for_pc(32'd68, 400);

            check_result(32'h00000000, 32'h00000001, "BLT taken: -2<5 x3=1");
            check_result(32'h00000004, 32'h00000002, "BLT not taken: 5 not < -2 x4=2");
        end
    endtask

    task test_bge;
        begin
            test_num = 14;
            $display("\n========================================");
            $display("Test 14: BGE signed taken and not taken");
            $display("========================================");

            init_memory();

            memory[0] = 32'h00800093;
            memory[1] = 32'h00800113;
            memory[2] = 32'h0020D663;
            memory[3] = 32'h06300193;
            memory[4] = 32'h00000013;
            memory[5] = 32'h00100193;
            memory[6] = 32'hFFF00213;
            memory[7] = 32'h00125663;
            memory[8] = 32'h00200293;
            memory[9] = 32'h00C0006F;
            memory[10] = 32'h00000013;
            memory[11] = 32'h00000013;
            memory[12] = 32'h00302023;
            memory[13] = 32'h00502223;
            memory[14] = 32'h0180006F;

            reset_processor();
            wait_for_pc(32'd72, 400);

            check_result(32'h00000000, 32'h00000001, "BGE taken: 8>=8 x3=1");
            check_result(32'h00000004, 32'h00000002, "BGE not taken: -1 not >=8 x5=2");
        end
    endtask

    task test_bltu;
        begin
            test_num = 15;
            $display("\n========================================");
            $display("Test 15: BLTU unsigned taken and not taken");
            $display("========================================");

            init_memory();

            memory[0] = 32'h00200093;
            memory[1] = 32'hFFF00113;
            memory[2] = 32'h0020E663;
            memory[3] = 32'h06300193;
            memory[4] = 32'h00000013;
            memory[5] = 32'h00100193;
            memory[6] = 32'h00116663;
            memory[7] = 32'h00200213;
            memory[8] = 32'h00C0006F;
            memory[9] = 32'h00000013;
            memory[10] = 32'h00000013;
            memory[11] = 32'h00302023;
            memory[12] = 32'h00402223;
            memory[13] = 32'h0140006F;

            reset_processor();
            wait_for_pc(32'd68, 400);

            check_result(32'h00000000, 32'h00000001, "BLTU taken: 2 <u 0xFFFFFFFF x3=1");
            check_result(32'h00000004, 32'h00000002, "BLTU not taken: big not <u 2 x4=2");
        end
    endtask

    task test_bgeu;
        begin
            test_num = 16;
            $display("\n========================================");
            $display("Test 16: BGEU unsigned taken and not taken");
            $display("========================================");

            init_memory();

            memory[0] = 32'hFFF00093;
            memory[1] = 32'h00500113;
            memory[2] = 32'h0020F663;
            memory[3] = 32'h06300193;
            memory[4] = 32'h00000013;
            memory[5] = 32'h00100193;
            memory[6] = 32'h00117663;
            memory[7] = 32'h00200213;
            memory[8] = 32'h00C0006F;
            memory[9] = 32'h00000013;
            memory[10] = 32'h00000013;
            memory[11] = 32'h00302023;
            memory[12] = 32'h00402223;
            memory[13] = 32'h0140006F;

            reset_processor();
            wait_for_pc(32'd68, 400);

            check_result(32'h00000000, 32'h00000001, "BGEU taken: big >=u 5 x3=1");
            check_result(32'h00000004, 32'h00000002, "BGEU not taken: 5 not >=u big x4=2");
        end
    endtask

    task test_jal;
        begin
            test_num = 17;
            $display("\n========================================");
            $display("Test 17: JAL jump and link");
            $display("========================================");

            init_memory();

            memory[0] = 32'h010000EF;
            memory[1] = 32'h06300113;
            memory[2] = 32'h00000013;
            memory[3] = 32'h00000013;
            memory[4] = 32'h04D00113;
            memory[5] = 32'h00102023;
            memory[6] = 32'h00202223;
            memory[7] = 32'h0180006F;

            reset_processor();
            wait_for_pc(32'd32, 400);

            check_result(32'h00000000, 32'h00000004, "JAL link=PC+4=4");
            check_result(32'h00000004, 32'h0000004D, "JAL jumped to target x2=77");
        end
    endtask

    task test_jalr;
        begin
            test_num = 18;
            $display("\n========================================");
            $display("Test 18: JALR indirect jump and link");
            $display("========================================");

            init_memory();

            // BUG FIX: was 0x01C00093 (addi x1,x0,28).
            // x1=28 made JALR jump to addr 28, skipping addi x3=55 at addr 24.
            // Correct value: x1=24 so JALR target = 24 = address of the subroutine.
            memory[0] = 32'h01800093;  // addi x1, x0, 24  -> x1 = 24
            memory[1] = 32'h00008167;  // jalr x2, x1, 0   -> x2=PC+4=8, PC=24
            memory[2] = 32'h06300193;  // addi x3, x0, 99  -> SKIPPED (PC jumps to 24)
            memory[3] = 32'h00000013;  // nop
            memory[4] = 32'h00000013;  // nop
            memory[5] = 32'h00000013;  // nop
            memory[6] = 32'h03700193;  // addi x3, x0, 55  -> x3=55  (JALR lands here)
            memory[7] = 32'h00202023;  // sw x2, 0(x0)     -> mem[0] = 8
            memory[8] = 32'h00302223;  // sw x3, 4(x0)     -> mem[1] = 55
            memory[9] = 32'h0180006F;  // jal x0, +24      -> loop away (timeout OK)

            reset_processor();
            wait_for_pc(32'd56, 400);

            check_result(32'h00000000, 32'h00000008, "JALR link=PC+4=8");
            check_result(32'h00000004, 32'h00000037, "JALR jumped to target x3=55");
        end
    endtask

    task test_lui;
        begin
            test_num = 19;
            $display("\n========================================");
            $display("Test 19: LUI load upper immediate");
            $display("========================================");

            init_memory();

            memory[0] = 32'hABCDE0B7;
            memory[1] = 32'h12308093;
            memory[2] = 32'h00102023;
            memory[3] = 32'h00C0006F;

            reset_processor();
            wait_for_pc(32'd12, 400);

            check_result(32'h00000000, 32'hABCDE123, "LUI+ADDI=0xABCDE123");
        end
    endtask

    task test_auipc;
        begin
            test_num = 20;
            $display("\n========================================");
            $display("Test 20: AUIPC add upper immediate to PC");
            $display("========================================");

            init_memory();

            memory[0] = 32'h00000013;
            memory[1] = 32'h00000013;
            memory[2] = 32'h00002097;
            memory[3] = 32'h00102023;
            memory[4] = 32'h00C0006F;

            reset_processor();
            wait_for_pc(32'd16, 400);

            check_result(32'h00000000, 32'h00002008, "AUIPC: PC=8 + 0x2000 = 0x2008");
        end
    endtask

    task test_x0_zero;
        begin
            test_num = 21;
            $display("\n========================================");
            $display("Test 21: x0 always zero");
            $display("========================================");

            init_memory();

            memory[0] = 32'h05500013;
            memory[1] = 32'hFFFFF037;
            memory[2] = 32'h03300093;
            memory[3] = 32'h00002023;
            memory[4] = 32'h00102223;
            memory[5] = 32'h0140006F;

            reset_processor();
            wait_for_pc(32'd20, 400);

            check_result(32'h00000000, 32'h00000000, "x0 stays 0 after write attempts");
            check_result(32'h00000004, 32'h00000033, "x1 written normally from x0=0");
        end
    endtask

    task test_loop_blt;
        begin
            test_num = 22;
            $display("\n========================================");
            $display("Test 22: Loop sum 1 to 7 using BLT");
            $display("========================================");

            init_memory();

            memory[0] = 32'h00000093;
            memory[1] = 32'h00100113;
            memory[2] = 32'h00800193;
            memory[3] = 32'h002080B3;
            memory[4] = 32'h00110113;
            memory[5] = 32'hFE314CE3;
            memory[6] = 32'h00102023;
            memory[7] = 32'h01C0006F;

            reset_processor();
            wait_for_pc(32'd28, 400);

            check_result(32'h00000000, 32'h0000001C, "Loop sum 1..7=28");
        end
    endtask

    task test_store_load_pattern;
        begin
            test_num = 23;
            $display("\n========================================");
            $display("Test 23: SB SH LW full word pattern");
            $display("========================================");

            init_memory();

            memory[0] = 32'h60000093;
            memory[1] = 32'h0CD00113;
            memory[2] = 32'h7EF00193;
            memory[3] = 32'h00208023;
            memory[4] = 32'h00309123;
            memory[5] = 32'h0000A203;
            memory[6] = 32'h00402023;
            memory[7] = 32'h01C0006F;

            reset_processor();
            wait_for_pc(32'd28, 400);

            check_result(32'h00000000, 32'h07EF00CD, "SB+SH verified by LW: 0x07EF00CD");
        end
    endtask

    initial begin
        $display("========================================");
        $display("RISC-V RV32I Testbench - 24112083");
        $display("Covers all RV32I instructions from PDF");
        $display("========================================");

        passed_tests = 0;
        total_tests  = 0;
        test_num     = 0;

        test_add_sub();
        test_xor_or_and();
        test_sll_srl_sra();
        test_slt_sltu();
        test_addi_xori_ori_andi();
        test_slli_srli_srai();
        test_slti_sltiu();
        test_lb_lh_lw();
        test_lbu_lhu();
        test_sb_sh_sw();
        test_beq();
        test_bne();
        test_blt();
        test_bge();
        test_bltu();
        test_bgeu();
        test_jal();
        test_jalr();
        test_lui();
        test_auipc();
        test_x0_zero();
        test_loop_blt();
        test_store_load_pattern();

        $display("\n========================================");
        $display("TEST SUMMARY");
        $display("========================================");
        $display("Passed: %0d/%0d tests", passed_tests, total_tests);
        $display("Score: %0d%%", (passed_tests * 100) / total_tests);
        $display("========================================\n");

        if (passed_tests == total_tests)
            $display("*** ALL TESTS PASSED ***");
        else
            $display("*** SOME TESTS FAILED ***");

        $finish;
    end

    initial begin
        #2000000;
        $display("\n[ERROR] Simulation timeout");
        $display("Passed: %0d/%0d tests before timeout", passed_tests, total_tests);
        $finish;
    end

endmodule
