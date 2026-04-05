`timescale 1ns/1ps

// ============================================================
// Full RV32I Testbench – every instruction individually tested
// Compatible with riscv_processor module interface
// ============================================================

module riscv_tb_full;

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
        .clk      (clk),
        .mem_addr (mem_addr),
        .mem_wdata(mem_wdata),
        .mem_wmask(mem_wmask),
        .mem_rdata(mem_rdata),
        .mem_rstrb(mem_rstrb),
        .mem_rbusy(mem_rbusy),
        .mem_wbusy(mem_wbusy),
        .reset    (reset)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Memory read
    always @(posedge clk) begin
        if (mem_rstrb)
            read_data <= memory[mem_addr[31:2]];
    end
    assign mem_rdata = read_data;

    // Memory write (byte-masked)
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
        if (!reset) cycle_count <= 0;
        else        cycle_count <= cycle_count + 1;
    end

    // --------------------------------------------------------
    // Helper tasks
    // --------------------------------------------------------
    task init_memory;
        begin
            for (i = 0; i < 4096; i = i + 1)
                memory[i] = 32'h00000013; // NOP (addi x0,x0,0)
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
                if (mem_addr == target_pc && mem_rstrb)
                    j = max_cycles;
            end
        end
    endtask

    task check_result;
        input [31:0]    addr;
        input [31:0]    expected;
        input [200*8:1] test_name;
        begin
            total_tests = total_tests + 1;
            if (memory[addr[31:2]] === expected) begin
                $display("[PASS] Test %0d: %s", test_num, test_name);
                $display("       Expected: 0x%08h  Got: 0x%08h", expected, memory[addr[31:2]]);
                passed_tests = passed_tests + 1;
            end else begin
                $display("[FAIL] Test %0d: %s", test_num, test_name);
                $display("       Expected: 0x%08h  Got: 0x%08h", expected, memory[addr[31:2]]);
            end
        end
    endtask

    // ============================================================
    // TEST 1 – ADD
    // ============================================================
    task test_add;
        begin
            test_num = 1;
            $display("\n========================================");
            $display("Test 1: ADD");
            $display("========================================");
            init_memory();
            //  addi x1, x0, 15      -> x1 = 15
            memory[0] = 32'h00F00093;
            //  addi x2, x0, 27      -> x2 = 27
            memory[1] = 32'h01B00113;
            //  add  x3, x1, x2      -> x3 = 42
            memory[2] = 32'h002081B3;
            //  sw   x3, 0(x0)
            memory[3] = 32'h00302023;
            //  jal  x0, 0 (loop)
            memory[4] = 32'h0000006F;

            reset_processor();
            wait_for_pc(32'd16, 300);
            check_result(32'h00000000, 32'h0000002A, "ADD: 15+27=42");
        end
    endtask

    // ============================================================
    // TEST 2 – SUB
    // ============================================================
    task test_sub;
        begin
            test_num = 2;
            $display("\n========================================");
            $display("Test 2: SUB");
            $display("========================================");
            init_memory();
            //  addi x1, x0, 50
            memory[0] = 32'h03200093;
            //  addi x2, x0, 13
            memory[1] = 32'h00D00113;
            //  sub  x3, x1, x2      -> x3 = 37
            memory[2] = 32'h402081B3;
            //  sw   x3, 0(x0)
            memory[3] = 32'h00302023;
            memory[4] = 32'h0000006F;

            reset_processor();
            wait_for_pc(32'd16, 300);
            check_result(32'h00000000, 32'h00000025, "SUB: 50-13=37");
        end
    endtask

    // ============================================================
    // TEST 3 – XOR
    // ============================================================
    task test_xor;
        begin
            test_num = 3;
            $display("\n========================================");
            $display("Test 3: XOR");
            $display("========================================");
            init_memory();
            //  addi x1, x0, 0xA5
            memory[0] = 32'h0A500093;
            //  addi x2, x0, 0x5A
            memory[1] = 32'h05A00113;
            //  xor  x3, x1, x2      -> x3 = 0xFF
            memory[2] = 32'h0020C1B3;
            //  sw   x3, 0(x0)
            memory[3] = 32'h00302023;
            memory[4] = 32'h0000006F;

            reset_processor();
            wait_for_pc(32'd16, 300);
            check_result(32'h00000000, 32'h000000FF, "XOR: 0xA5^0x5A=0xFF");
        end
    endtask

    // ============================================================
    // TEST 4 – OR
    // ============================================================
    task test_or;
        begin
            test_num = 4;
            $display("\n========================================");
            $display("Test 4: OR");
            $display("========================================");
            init_memory();
            //  addi x1, x0, 0xF0
            memory[0] = 32'h0F000093;
            //  addi x2, x0, 0x0F
            memory[1] = 32'h00F00113;
            //  or   x3, x1, x2      -> x3 = 0xFF
            memory[2] = 32'h0020E1B3;
            //  sw   x3, 0(x0)
            memory[3] = 32'h00302023;
            memory[4] = 32'h0000006F;

            reset_processor();
            wait_for_pc(32'd16, 300);
            check_result(32'h00000000, 32'h000000FF, "OR: 0xF0|0x0F=0xFF");
        end
    endtask

    // ============================================================
    // TEST 5 – AND
    // ============================================================
    task test_and;
        begin
            test_num = 5;
            $display("\n========================================");
            $display("Test 5: AND");
            $display("========================================");
            init_memory();
            //  addi x1, x0, 0xFF
            memory[0] = 32'h0FF00093;
            //  addi x2, x0, 0x0F
            memory[1] = 32'h00F00113;
            //  and  x3, x1, x2      -> x3 = 0x0F
            memory[2] = 32'h0020F1B3;
            //  sw   x3, 0(x0)
            memory[3] = 32'h00302023;
            memory[4] = 32'h0000006F;

            reset_processor();
            wait_for_pc(32'd16, 300);
            check_result(32'h00000000, 32'h0000000F, "AND: 0xFF&0x0F=0x0F");
        end
    endtask

    // ============================================================
    // TEST 6 – SLL
    // ============================================================
    task test_sll;
        begin
            test_num = 6;
            $display("\n========================================");
            $display("Test 6: SLL");
            $display("========================================");
            init_memory();
            //  addi x1, x0, 1
            memory[0] = 32'h00100093;
            //  addi x2, x0, 8
            memory[1] = 32'h00800113;
            //  sll  x3, x1, x2      -> x3 = 256
            memory[2] = 32'h002091B3;
            //  sw   x3, 0(x0)
            memory[3] = 32'h00302023;
            memory[4] = 32'h0000006F;

            reset_processor();
            wait_for_pc(32'd16, 300);
            check_result(32'h00000000, 32'h00000100, "SLL: 1<<8=256");
        end
    endtask

    // ============================================================
    // TEST 7 – SRL
    // ============================================================
    task test_srl;
        begin
            test_num = 7;
            $display("\n========================================");
            $display("Test 7: SRL");
            $display("========================================");
            init_memory();
            //  lui  x1, 0x80000      -> x1 = 0x80000000
            memory[0] = 32'h800000B7;
            //  addi x2, x0, 4
            memory[1] = 32'h00400113;
            //  srl  x3, x1, x2      -> x3 = 0x08000000
            memory[2] = 32'h0020D1B3;
            //  sw   x3, 0(x0)
            memory[3] = 32'h00302023;
            memory[4] = 32'h0000006F;

            reset_processor();
            wait_for_pc(32'd16, 300);
            check_result(32'h00000000, 32'h08000000, "SRL: 0x80000000>>4=0x08000000");
        end
    endtask

    // ============================================================
    // TEST 8 – SRA
    // ============================================================
    task test_sra;
        begin
            test_num = 8;
            $display("\n========================================");
            $display("Test 8: SRA (arithmetic shift, sign-extends)");
            $display("========================================");
            init_memory();
            //  lui  x1, 0x80000      -> x1 = 0x80000000
            memory[0] = 32'h800000B7;
            //  addi x2, x0, 4
            memory[1] = 32'h00400113;
            //  sra  x3, x1, x2      -> x3 = 0xF8000000
            memory[2] = 32'h4020D1B3;
            //  sw   x3, 0(x0)
            memory[3] = 32'h00302023;
            memory[4] = 32'h0000006F;

            reset_processor();
            wait_for_pc(32'd16, 300);
            check_result(32'h00000000, 32'hF8000000, "SRA: 0x80000000>>4=0xF8000000");
        end
    endtask

    // ============================================================
    // TEST 9 – SLT
    // ============================================================
    task test_slt;
        begin
            test_num = 9;
            $display("\n========================================");
            $display("Test 9: SLT (signed set-less-than)");
            $display("========================================");
            init_memory();
            //  addi x1, x0, -1      -> x1 = 0xFFFFFFFF
            memory[0] = 32'hFFF00093;
            //  addi x2, x0, 1
            memory[1] = 32'h00100113;
            //  slt  x3, x1, x2      -> x3 = 1 (-1 < 1 signed)
            memory[2] = 32'h0020A1B3;
            //  slt  x4, x2, x1      -> x4 = 0 (1 not < -1 signed)
            memory[3] = 32'h00112233;
            //  sw   x3, 0(x0)
            memory[4] = 32'h00302023;
            //  sw   x4, 4(x0)
            memory[5] = 32'h00402223;
            memory[6] = 32'h0000006F;

            reset_processor();
            wait_for_pc(32'd24, 300);
            check_result(32'h00000000, 32'h00000001, "SLT: -1 < 1 (signed) = 1");
            check_result(32'h00000004, 32'h00000000, "SLT: 1 not < -1 (signed) = 0");
        end
    endtask

    // ============================================================
    // TEST 10 – SLTU
    // ============================================================
    task test_sltu;
        begin
            test_num = 10;
            $display("\n========================================");
            $display("Test 10: SLTU (unsigned set-less-than)");
            $display("========================================");
            init_memory();
            //  addi x1, x0, 2
            memory[0] = 32'h00200093;
            //  addi x2, x0, -1      -> x2 = 0xFFFFFFFF (unsigned big)
            memory[1] = 32'hFFF00113;
            //  sltu x3, x1, x2      -> x3 = 1 (2 <u 0xFFFFFFFF)
            memory[2] = 32'h0020B1B3;
            //  sltu x4, x2, x1      -> x4 = 0
            memory[3] = 32'h00113233;
            //  sw   x3, 0(x0)
            memory[4] = 32'h00302023;
            //  sw   x4, 4(x0)
            memory[5] = 32'h00402223;
            memory[6] = 32'h0000006F;

            reset_processor();
            wait_for_pc(32'd24, 300);
            check_result(32'h00000000, 32'h00000001, "SLTU: 2 <u 0xFFFFFFFF = 1");
            check_result(32'h00000004, 32'h00000000, "SLTU: 0xFFFFFFFF not <u 2 = 0");
        end
    endtask

    // ============================================================
    // TEST 11 – ADDI
    // ============================================================
    task test_addi;
        begin
            test_num = 11;
            $display("\n========================================");
            $display("Test 11: ADDI");
            $display("========================================");
            init_memory();
            //  addi x1, x0, 100     -> x1 = 100
            memory[0] = 32'h06400093;
            //  addi x2, x1, -100    -> x2 = 0
            memory[1] = 32'hF9C08113;
            //  sw   x1, 0(x0)
            memory[2] = 32'h00102023;
            //  sw   x2, 4(x0)
            memory[3] = 32'h00202223;
            memory[4] = 32'h0000006F;

            reset_processor();
            wait_for_pc(32'd16, 300);
            check_result(32'h00000000, 32'h00000064, "ADDI: 0+100=100");
            check_result(32'h00000004, 32'h00000000, "ADDI: 100+(-100)=0");
        end
    endtask

    // ============================================================
    // TEST 12 – XORI
    // ============================================================
    task test_xori;
        begin
            test_num = 12;
            $display("\n========================================");
            $display("Test 12: XORI");
            $display("========================================");
            init_memory();
            //  addi x1, x0, 0x55
            memory[0] = 32'h05500093;
            //  xori x2, x1, 0xFF    -> x2 = 0xAA
            memory[1] = 32'h0FF0C113;
            //  sw   x2, 0(x0)
            memory[2] = 32'h00202023;
            memory[3] = 32'h0000006F;

            reset_processor();
            wait_for_pc(32'd12, 300);
            check_result(32'h00000000, 32'h000000AA, "XORI: 0x55^0xFF=0xAA");
        end
    endtask

    // ============================================================
    // TEST 13 – ORI
    // ============================================================
    task test_ori;
        begin
            test_num = 13;
            $display("\n========================================");
            $display("Test 13: ORI");
            $display("========================================");
            init_memory();
            //  addi x1, x0, 0x30
            memory[0] = 32'h03000093;
            //  ori  x2, x1, 0x0F    -> x2 = 0x3F
            memory[1] = 32'h00F0E113;
            //  sw   x2, 0(x0)
            memory[2] = 32'h00202023;
            memory[3] = 32'h0000006F;

            reset_processor();
            wait_for_pc(32'd12, 300);
            check_result(32'h00000000, 32'h0000003F, "ORI: 0x30|0x0F=0x3F");
        end
    endtask

    // ============================================================
    // TEST 14 – ANDI
    // ============================================================
    task test_andi;
        begin
            test_num = 14;
            $display("\n========================================");
            $display("Test 14: ANDI");
            $display("========================================");
            init_memory();
            //  addi x1, x0, 0xFF
            memory[0] = 32'h0FF00093;
            //  andi x2, x1, 0x55    -> x2 = 0x55
            memory[1] = 32'h0550F113;
            //  sw   x2, 0(x0)
            memory[2] = 32'h00202023;
            memory[3] = 32'h0000006F;

            reset_processor();
            wait_for_pc(32'd12, 300);
            check_result(32'h00000000, 32'h00000055, "ANDI: 0xFF&0x55=0x55");
        end
    endtask

    // ============================================================
    // TEST 15 – SLLI
    // ============================================================
    task test_slli;
        begin
            test_num = 15;
            $display("\n========================================");
            $display("Test 15: SLLI");
            $display("========================================");
            init_memory();
            //  addi x1, x0, 1
            memory[0] = 32'h00100093;
            //  slli x2, x1, 10      -> x2 = 1024
            memory[1] = 32'h00A09113;
            //  sw   x2, 0(x0)
            memory[2] = 32'h00202023;
            memory[3] = 32'h0000006F;

            reset_processor();
            wait_for_pc(32'd12, 300);
            check_result(32'h00000000, 32'h00000400, "SLLI: 1<<10=1024");
        end
    endtask

    // ============================================================
    // TEST 16 – SRLI
    // ============================================================
    task test_srli;
        begin
            test_num = 16;
            $display("\n========================================");
            $display("Test 16: SRLI");
            $display("========================================");
            init_memory();
            //  lui  x1, 0x80000     -> x1 = 0x80000000
            memory[0] = 32'h800000B7;
            //  srli x2, x1, 3       -> x2 = 0x10000000
            memory[1] = 32'h0030D113;
            //  sw   x2, 0(x0)
            memory[2] = 32'h00202023;
            memory[3] = 32'h0000006F;

            reset_processor();
            wait_for_pc(32'd12, 300);
            check_result(32'h00000000, 32'h10000000, "SRLI: 0x80000000>>3=0x10000000");
        end
    endtask

    // ============================================================
    // TEST 17 – SRAI
    // ============================================================
    task test_srai;
        begin
            test_num = 17;
            $display("\n========================================");
            $display("Test 17: SRAI (sign extends)");
            $display("========================================");
            init_memory();
            //  lui  x1, 0x80000     -> x1 = 0x80000000
            memory[0] = 32'h800000B7;
            //  srai x2, x1, 3       -> x2 = 0xF0000000
            memory[1] = 32'h4030D113;
            //  sw   x2, 0(x0)
            memory[2] = 32'h00202023;
            memory[3] = 32'h0000006F;

            reset_processor();
            wait_for_pc(32'd12, 300);
            check_result(32'h00000000, 32'hF0000000, "SRAI: 0x80000000>>3=0xF0000000");
        end
    endtask

    // ============================================================
    // TEST 18 – SLTI
    // ============================================================
    task test_slti;
        begin
            test_num = 18;
            $display("\n========================================");
            $display("Test 18: SLTI");
            $display("========================================");
            init_memory();
            //  addi x1, x0, -5      -> x1 = -5
            memory[0] = 32'hFFB00093;
            //  slti x2, x1, 0       -> x2 = 1 (-5 < 0)
            memory[1] = 32'h0000A113;
            //  slti x3, x1, -10     -> x3 = 0 (-5 not < -10)
            memory[2] = 32'hFF60A193;
            //  sw   x2, 0(x0)
            memory[3] = 32'h00202023;
            //  sw   x3, 4(x0)
            memory[4] = 32'h00302223;
            memory[5] = 32'h0000006F;

            reset_processor();
            wait_for_pc(32'd20, 300);
            check_result(32'h00000000, 32'h00000001, "SLTI: -5 < 0 = 1");
            check_result(32'h00000004, 32'h00000000, "SLTI: -5 not < -10 = 0");
        end
    endtask

    // ============================================================
    // TEST 19 – SLTIU
    // ============================================================
    task test_sltiu;
        begin
            test_num = 19;
            $display("\n========================================");
            $display("Test 19: SLTIU");
            $display("========================================");
            init_memory();
            //  addi x1, x0, 3
            memory[0] = 32'h00300093;
            //  sltiu x2, x1, 10     -> x2 = 1 (3 <u 10)
            memory[1] = 32'h00A0B113;
            //  sltiu x3, x1, 2      -> x3 = 0 (3 not <u 2)
            memory[2] = 32'h0020B193;
            //  sw   x2, 0(x0)
            memory[3] = 32'h00202023;
            //  sw   x3, 4(x0)
            memory[4] = 32'h00302223;
            memory[5] = 32'h0000006F;

            reset_processor();
            wait_for_pc(32'd20, 300);
            check_result(32'h00000000, 32'h00000001, "SLTIU: 3 <u 10 = 1");
            check_result(32'h00000004, 32'h00000000, "SLTIU: 3 not <u 2 = 0");
        end
    endtask

    // ============================================================
    // TEST 20 – LW
    // ============================================================
    task test_lw;
        begin
            test_num = 20;
            $display("\n========================================");
            $display("Test 20: LW (load word)");
            $display("========================================");
            init_memory();
            memory[256] = 32'hDEADBEEF; // address 0x400
            //  addi x1, x0, 0x400
            memory[0] = 32'h40000093;
            //  lw   x2, 0(x1)       -> x2 = 0xDEADBEEF
            memory[1] = 32'h0000A103;
            //  sw   x2, 0(x0)
            memory[2] = 32'h00202023;
            memory[3] = 32'h0000006F;

            reset_processor();
            wait_for_pc(32'd12, 300);
            check_result(32'h00000000, 32'hDEADBEEF, "LW: full 32-bit word");
        end
    endtask

    // ============================================================
    // TEST 21 – LH (signed half)
    // ============================================================
    task test_lh;
        begin
            test_num = 21;
            $display("\n========================================");
            $display("Test 21: LH (signed halfword load)");
            $display("========================================");
            init_memory();
            memory[256] = 32'h0000CAFE; // lower halfword 0xCAFE (negative)
            //  addi x1, x0, 0x400
            memory[0] = 32'h40000093;
            //  lh   x2, 0(x1)       -> sign-extend 0xCAFE -> 0xFFFFCAFE
            memory[1] = 32'h00009103;
            //  sw   x2, 0(x0)
            memory[2] = 32'h00202023;
            memory[3] = 32'h0000006F;

            reset_processor();
            wait_for_pc(32'd12, 300);
            check_result(32'h00000000, 32'hFFFFCAFE, "LH: 0xCAFE sign-extended");
        end
    endtask

    // ============================================================
    // TEST 22 – LB (signed byte)
    // ============================================================
    task test_lb;
        begin
            test_num = 22;
            $display("\n========================================");
            $display("Test 22: LB (signed byte load)");
            $display("========================================");
            init_memory();
            memory[256] = 32'h000000F1; // byte 0xF1 (negative)
            //  addi x1, x0, 0x400
            memory[0] = 32'h40000093;
            //  lb   x2, 0(x1)       -> sign-extend 0xF1 -> 0xFFFFFFF1
            memory[1] = 32'h00008103;
            //  sw   x2, 0(x0)
            memory[2] = 32'h00202023;
            memory[3] = 32'h0000006F;

            reset_processor();
            wait_for_pc(32'd12, 300);
            check_result(32'h00000000, 32'hFFFFFFF1, "LB: 0xF1 sign-extended");
        end
    endtask

    // ============================================================
    // TEST 23 – LBU (unsigned byte)
    // ============================================================
    task test_lbu;
        begin
            test_num = 23;
            $display("\n========================================");
            $display("Test 23: LBU (zero-extended byte load)");
            $display("========================================");
            init_memory();
            memory[256] = 32'h000000F1;
            //  addi x1, x0, 0x400
            memory[0] = 32'h40000093;
            //  lbu  x2, 0(x1)       -> zero-extend 0xF1 -> 0x000000F1
            memory[1] = 32'h0000C103;
            //  sw   x2, 0(x0)
            memory[2] = 32'h00202023;
            memory[3] = 32'h0000006F;

            reset_processor();
            wait_for_pc(32'd12, 300);
            check_result(32'h00000000, 32'h000000F1, "LBU: 0xF1 zero-extended");
        end
    endtask

    // ============================================================
    // TEST 24 – LHU (unsigned half)
    // ============================================================
    task test_lhu;
        begin
            test_num = 24;
            $display("\n========================================");
            $display("Test 24: LHU (zero-extended halfword load)");
            $display("========================================");
            init_memory();
            memory[256] = 32'h0000CAFE;
            //  addi x1, x0, 0x400
            memory[0] = 32'h40000093;
            //  lhu  x2, 0(x1)       -> zero-extend 0xCAFE -> 0x0000CAFE
            memory[1] = 32'h0000D103;
            //  sw   x2, 0(x0)
            memory[2] = 32'h00202023;
            memory[3] = 32'h0000006F;

            reset_processor();
            wait_for_pc(32'd12, 300);
            check_result(32'h00000000, 32'h0000CAFE, "LHU: 0xCAFE zero-extended");
        end
    endtask

    // ============================================================
    // TEST 25 – SW
    // ============================================================
    task test_sw;
        begin
            test_num = 25;
            $display("\n========================================");
            $display("Test 25: SW (store word)");
            $display("========================================");
            init_memory();
            //  addi x1, x0, 0x12345 (uses lui + addi)
            //  lui  x1, 0x12345
            memory[0] = 32'h123450B7;
            //  addi x1, x1, 0x678   -> x1 = 0x12345678
            memory[1] = 32'h67808093;
            //  sw   x1, 0(x0)
            memory[2] = 32'h00102023;
            memory[3] = 32'h0000006F;

            reset_processor();
            wait_for_pc(32'd12, 300);
            check_result(32'h00000000, 32'h12345678, "SW: stored 0x12345678");
        end
    endtask

    // ============================================================
    // TEST 26 – SH
    // ============================================================
    task test_sh;
        begin
            test_num = 26;
            $display("\n========================================");
            $display("Test 26: SH (store halfword)");
            $display("========================================");
            init_memory();
            memory[128] = 32'hFFFFFFFF; // pre-fill addr 0x200
            //  addi x1, x0, 0x200   -> base address
            memory[0] = 32'h20000093;
            //  addi x2, x0, 0xAB
            memory[1] = 32'h0AB00113;
            //  sh   x2, 0(x1)       -> store lower 16 bits at addr 0x200
            memory[2] = 32'h00209023;
            //  lw   x3, 0(x1)       -> read back to verify mask
            memory[3] = 32'h0000A183;
            //  sw   x3, 0(x0)
            memory[4] = 32'h00302023;
            memory[5] = 32'h0000006F;

            reset_processor();
            wait_for_pc(32'd20, 300);
            check_result(32'h00000000, 32'hFFFF00AB, "SH: lower half=0x00AB, upper preserved");
        end
    endtask

    // ============================================================
    // TEST 27 – SB
    // ============================================================
    task test_sb;
        begin
            test_num = 27;
            $display("\n========================================");
            $display("Test 27: SB (store byte)");
            $display("========================================");
            init_memory();
            memory[128] = 32'hFFFFFFFF; // pre-fill addr 0x200
            //  addi x1, x0, 0x200
            memory[0] = 32'h20000093;
            //  addi x2, x0, 0x42
            memory[1] = 32'h04200113;
            //  sb   x2, 0(x1)       -> store byte 0x42 at addr 0x200
            memory[2] = 32'h00208023;
            //  lw   x3, 0(x1)
            memory[3] = 32'h0000A183;
            //  sw   x3, 0(x0)
            memory[4] = 32'h00302023;
            memory[5] = 32'h0000006F;

            reset_processor();
            wait_for_pc(32'd20, 300);
            check_result(32'h00000000, 32'hFFFFFF42, "SB: byte0=0x42, rest preserved");
        end
    endtask

    // ============================================================
    // TEST 28 – BEQ
    // ============================================================
    task test_beq;
        begin
            test_num = 28;
            $display("\n========================================");
            $display("Test 28: BEQ (branch if equal)");
            $display("========================================");
            init_memory();
            //  addi x1, x0, 7
            memory[0] = 32'h00700093;
            //  addi x2, x0, 7
            memory[1] = 32'h00700113;
            //  addi x3, x0, 5
            memory[2] = 32'h00500193;
            //  beq  x1, x2, +12     -> taken, skips next sw
            memory[3] = 32'h00208663;
            //  addi x4, x0, 99      -> SKIPPED
            memory[4] = 32'h06300213;
            //  nop
            memory[5] = 32'h00000013;
            //  addi x4, x0, 1       -> executed
            memory[6] = 32'h00100213;
            //  beq  x1, x3, +8     -> NOT taken (7 != 5)
            memory[7] = 32'h00308463;
            //  addi x5, x0, 2       -> executed
            memory[8] = 32'h00200293;
            //  sw   x4, 0(x0)
            memory[9] = 32'h00402023;
            //  sw   x5, 4(x0)
            memory[10] = 32'h00502223;
            memory[11] = 32'h0000006F;

            reset_processor();
            wait_for_pc(32'd44, 300);
            check_result(32'h00000000, 32'h00000001, "BEQ taken: 7==7, x4=1");
            check_result(32'h00000004, 32'h00000002, "BEQ not taken: 7!=5, x5=2");
        end
    endtask

    // ============================================================
    // TEST 29 – BNE
    // ============================================================
    task test_bne;
        begin
            test_num = 29;
            $display("\n========================================");
            $display("Test 29: BNE (branch if not equal)");
            $display("========================================");
            init_memory();
            //  addi x1, x0, 3
            memory[0] = 32'h00300093;
            //  addi x2, x0, 7
            memory[1] = 32'h00700113;
            //  addi x3, x0, 3
            memory[2] = 32'h00300193;
            //  bne  x1, x2, +12    -> taken (3!=7)
            memory[3] = 32'h00209663;
            //  addi x4, x0, 99     -> SKIPPED
            memory[4] = 32'h06300213;
            //  nop
            memory[5] = 32'h00000013;
            //  addi x4, x0, 1      -> executed
            memory[6] = 32'h00100213;
            //  bne  x1, x3, +8    -> NOT taken (3==3)
            memory[7] = 32'h00309463;
            //  addi x5, x0, 2     -> executed
            memory[8] = 32'h00200293;
            //  sw   x4, 0(x0)
            memory[9] = 32'h00402023;
            //  sw   x5, 4(x0)
            memory[10] = 32'h00502223;
            memory[11] = 32'h0000006F;

            reset_processor();
            wait_for_pc(32'd44, 300);
            check_result(32'h00000000, 32'h00000001, "BNE taken: 3!=7, x4=1");
            check_result(32'h00000004, 32'h00000002, "BNE not taken: 3==3, x5=2");
        end
    endtask

    // ============================================================
    // TEST 30 – BLT
    // ============================================================
    task test_blt;
        begin
            test_num = 30;
            $display("\n========================================");
            $display("Test 30: BLT (branch if less than, signed)");
            $display("========================================");
            init_memory();
            //  addi x1, x0, -2
            memory[0] = 32'hFFE00093;
            //  addi x2, x0, 5
            memory[1] = 32'h00500113;
            //  blt  x1, x2, +12    -> taken (-2 < 5)
            memory[2] = 32'h0020C663;
            //  addi x3, x0, 99     -> SKIPPED
            memory[3] = 32'h06300193;
            memory[4] = 32'h00000013;
            //  addi x3, x0, 1      -> executed
            memory[5] = 32'h00100193;
            //  blt  x2, x1, +8    -> NOT taken (5 not < -2)
            memory[6] = 32'h00114463;
            //  addi x4, x0, 2     -> executed
            memory[7] = 32'h00200213;
            //  sw   x3, 0(x0)
            memory[8] = 32'h00302023;
            //  sw   x4, 4(x0)
            memory[9] = 32'h00402223;
            memory[10] = 32'h0000006F;

            reset_processor();
            wait_for_pc(32'd40, 300);
            check_result(32'h00000000, 32'h00000001, "BLT taken: -2 < 5, x3=1");
            check_result(32'h00000004, 32'h00000002, "BLT not taken: 5 not < -2, x4=2");
        end
    endtask

    // ============================================================
    // TEST 31 – BGE
    // ============================================================
    task test_bge;
        begin
            test_num = 31;
            $display("\n========================================");
            $display("Test 31: BGE (branch if >= signed)");
            $display("========================================");
            init_memory();
            //  addi x1, x0, 8
            memory[0] = 32'h00800093;
            //  addi x2, x0, 8
            memory[1] = 32'h00800113;
            //  bge  x1, x2, +12    -> taken (8 >= 8)
            memory[2] = 32'h0020D663;
            //  addi x3, x0, 99    -> SKIPPED
            memory[3] = 32'h06300193;
            memory[4] = 32'h00000013;
            //  addi x3, x0, 1     -> executed
            memory[5] = 32'h00100193;
            //  addi x4, x0, -1    -> x4 = -1
            memory[6] = 32'hFFF00213;
            //  bge  x4, x1, +8   -> NOT taken (-1 not >= 8)
            memory[7] = 32'h00125463;
            //  addi x5, x0, 2    -> executed
            memory[8] = 32'h00200293;
            //  sw   x3, 0(x0)
            memory[9] = 32'h00302023;
            //  sw   x5, 4(x0)
            memory[10] = 32'h00502223;
            memory[11] = 32'h0000006F;

            reset_processor();
            wait_for_pc(32'd44, 300);
            check_result(32'h00000000, 32'h00000001, "BGE taken: 8>=8, x3=1");
            check_result(32'h00000004, 32'h00000002, "BGE not taken: -1 not >=8, x5=2");
        end
    endtask

    // ============================================================
    // TEST 32 – BLTU
    // ============================================================
    task test_bltu;
        begin
            test_num = 32;
            $display("\n========================================");
            $display("Test 32: BLTU (branch if <u unsigned)");
            $display("========================================");
            init_memory();
            //  addi x1, x0, 2
            memory[0] = 32'h00200093;
            //  addi x2, x0, -1      -> 0xFFFFFFFF (huge unsigned)
            memory[1] = 32'hFFF00113;
            //  bltu x1, x2, +12    -> taken (2 <u 0xFFFFFFFF)
            memory[2] = 32'h0020E663;
            //  addi x3, x0, 99    -> SKIPPED
            memory[3] = 32'h06300193;
            memory[4] = 32'h00000013;
            //  addi x3, x0, 1     -> executed
            memory[5] = 32'h00100193;
            //  bltu x2, x1, +8   -> NOT taken (0xFFFFFFFF not <u 2)
            memory[6] = 32'h00116463;
            //  addi x4, x0, 2    -> executed
            memory[7] = 32'h00200213;
            //  sw   x3, 0(x0)
            memory[8] = 32'h00302023;
            //  sw   x4, 4(x0)
            memory[9] = 32'h00402223;
            memory[10] = 32'h0000006F;

            reset_processor();
            wait_for_pc(32'd40, 300);
            check_result(32'h00000000, 32'h00000001, "BLTU taken: 2 <u 0xFFFFFFFF, x3=1");
            check_result(32'h00000004, 32'h00000002, "BLTU not taken: big not <u 2, x4=2");
        end
    endtask

    // ============================================================
    // TEST 33 – BGEU
    // ============================================================
    task test_bgeu;
        begin
            test_num = 33;
            $display("\n========================================");
            $display("Test 33: BGEU (branch if >=u unsigned)");
            $display("========================================");
            init_memory();
            //  addi x1, x0, -1      -> 0xFFFFFFFF
            memory[0] = 32'hFFF00093;
            //  addi x2, x0, 5
            memory[1] = 32'h00500113;
            //  bgeu x1, x2, +12    -> taken (0xFFFFFFFF >=u 5)
            memory[2] = 32'h0020F663;
            //  addi x3, x0, 99    -> SKIPPED
            memory[3] = 32'h06300193;
            memory[4] = 32'h00000013;
            //  addi x3, x0, 1     -> executed
            memory[5] = 32'h00100193;
            //  bgeu x2, x1, +8   -> NOT taken (5 not >=u 0xFFFFFFFF)
            memory[6] = 32'h00117463;
            //  addi x4, x0, 2    -> executed
            memory[7] = 32'h00200213;
            //  sw   x3, 0(x0)
            memory[8] = 32'h00302023;
            //  sw   x4, 4(x0)
            memory[9] = 32'h00402223;
            memory[10] = 32'h0000006F;

            reset_processor();
            wait_for_pc(32'd40, 300);
            check_result(32'h00000000, 32'h00000001, "BGEU taken: 0xFFFFFFFF >=u 5, x3=1");
            check_result(32'h00000004, 32'h00000002, "BGEU not taken: 5 not >=u big, x4=2");
        end
    endtask

    // ============================================================
    // TEST 34 – JAL
    // ============================================================
    task test_jal;
        begin
            test_num = 34;
            $display("\n========================================");
            $display("Test 34: JAL (jump and link)");
            $display("========================================");
            init_memory();
            //  jal  x1, +16         -> x1 = PC+4 = 4, jump to addr 16
            memory[0] = 32'h010000EF;  // rd=x1 (bits[11:7]=00001)
            //  addi x2, x0, 99     -> SKIPPED (addr 4)
            memory[1] = 32'h06300113;
            //  nop                  -> addr 8
            memory[2] = 32'h00000013;
            //  nop                  -> addr 12
            memory[3] = 32'h00000013;
            //  addi x2, x0, 77     -> addr 16 (JAL lands here)
            memory[4] = 32'h04D00113;
            //  sw   x1, 0x100(x0)  -> store to high mem (not program area)
            memory[5] = 32'h10102023;
            //  sw   x2, 0x104(x0)
            memory[6] = 32'h10202223;
            //  jal  x0, 0 (loop)
            memory[7] = 32'h0000006F;

            reset_processor();
            wait_for_pc(32'd28, 300);
            check_result(32'h00000100, 32'h00000004, "JAL: link x1=PC+4=4");
            check_result(32'h00000104, 32'h0000004D, "JAL: jumped to +16, x2=77");
        end
    endtask

    // ============================================================
    // TEST 35 – JALR
    // ============================================================
    task test_jalr;
        begin
            test_num = 35;
            $display("\n========================================");
            $display("Test 35: JALR (jump and link register)");
            $display("========================================");
            init_memory();
            //  addi x1, x0, 24     -> x1 = 24 (target addr)
            memory[0] = 32'h01800093;
            //  jalr x2, x1, 0      -> x2=PC+4=8, PC=24
            memory[1] = 32'h00008167;
            //  addi x3, x0, 99     -> SKIPPED (addr 8)
            memory[2] = 32'h06300193;
            //  nop addr 12
            memory[3] = 32'h00000013;
            //  nop addr 16
            memory[4] = 32'h00000013;
            //  nop addr 20
            memory[5] = 32'h00000013;
            //  addi x3, x0, 55     -> addr 24 (JALR lands here)
            memory[6] = 32'h03700193;
            //  sw   x2, 0(x0)
            memory[7] = 32'h00202023;
            //  sw   x3, 4(x0)
            memory[8] = 32'h00302223;
            memory[9] = 32'h0000006F;

            reset_processor();
            wait_for_pc(32'd36, 300);
            check_result(32'h00000000, 32'h00000008, "JALR: link x2=PC+4=8");
            check_result(32'h00000004, 32'h00000037, "JALR: jumped to 24, x3=55");
        end
    endtask

    // ============================================================
    // TEST 36 – LUI
    // ============================================================
    task test_lui;
        begin
            test_num = 36;
            $display("\n========================================");
            $display("Test 36: LUI (load upper immediate)");
            $display("========================================");
            init_memory();
            //  lui  x1, 0xABCDE     -> x1 = 0xABCDE000
            memory[0] = 32'hABCDE0B7;
            //  sw   x1, 0(x0)
            memory[1] = 32'h00102023;
            memory[2] = 32'h0000006F;

            reset_processor();
            wait_for_pc(32'd8, 300);
            check_result(32'h00000000, 32'hABCDE000, "LUI: 0xABCDE<<12=0xABCDE000");
        end
    endtask

    // ============================================================
    // TEST 37 – AUIPC
    // ============================================================
    task test_auipc;
        begin
            test_num = 37;
            $display("\n========================================");
            $display("Test 37: AUIPC (add upper immediate to PC)");
            $display("========================================");
            init_memory();
            //  nop (addr 0)
            memory[0] = 32'h00000013;
            //  nop (addr 4)
            memory[1] = 32'h00000013;
            //  auipc x1, 0x1       -> x1 = PC(8) + 0x1000 = 0x1008
            memory[2] = 32'h00001097; // auipc x1, 1
            //  sw   x1, 0(x0)
            memory[3] = 32'h00102023;
            memory[4] = 32'h0000006F;

            reset_processor();
            wait_for_pc(32'd16, 300);
            check_result(32'h00000000, 32'h00001008, "AUIPC: PC=8 + 0x1000 = 0x1008");
        end
    endtask

    // ============================================================
    // TEST 38 – LUI + ADDI (build arbitrary 32-bit constant)
    // ============================================================
    task test_lui_addi_combo;
        begin
            test_num = 38;
            $display("\n========================================");
            $display("Test 38: LUI+ADDI = arbitrary 32-bit constant");
            $display("========================================");
            init_memory();
            //  lui  x1, 0xDEADB    -> x1 = 0xDEADB000
            memory[0] = 32'hDEADB0B7;
            //  addi x1, x1, 0x7EF  -> x1 = 0xDEADB7EF
            memory[1] = 32'h7EF08093;
            //  sw   x1, 0(x0)
            memory[2] = 32'h00102023;
            memory[3] = 32'h0000006F;

            reset_processor();
            wait_for_pc(32'd12, 300);
            check_result(32'h00000000, 32'hDEADB7EF, "LUI+ADDI: 0xDEADB7EF");
        end
    endtask

    // ============================================================
    // TEST 39 – x0 always reads as zero
    // ============================================================
    task test_x0_hardwired_zero;
        begin
            test_num = 39;
            $display("\n========================================");
            $display("Test 39: x0 hardwired to zero");
            $display("========================================");
            init_memory();
            //  addi x0, x0, 0xFF   -> should NOT change x0
            memory[0] = 32'h0FF00013;
            //  lui  x0, 0xFFFFF    -> should NOT change x0
            memory[1] = 32'hFFFFF037;
            //  addi x1, x0, 42    -> x1 = 42 (uses x0, must be 0)
            memory[2] = 32'h02A00093;
            //  sw   x0, 0(x0)
            memory[3] = 32'h00002023;
            //  sw   x1, 4(x0)
            memory[4] = 32'h00102223;
            memory[5] = 32'h0000006F;

            reset_processor();
            wait_for_pc(32'd20, 300);
            check_result(32'h00000000, 32'h00000000, "x0 stays 0 after write attempts");
            check_result(32'h00000004, 32'h0000002A, "x1 = x0+42 = 42 (x0 was 0)");
        end
    endtask

    // ============================================================
    // TEST 40 – Negative immediate sign extension (ADDI)
    // ============================================================
    task test_negative_imm;
        begin
            test_num = 40;
            $display("\n========================================");
            $display("Test 40: Negative immediate sign extension");
            $display("========================================");
            init_memory();
            //  addi x1, x0, -1     -> x1 = 0xFFFFFFFF
            memory[0] = 32'hFFF00093;
            //  addi x2, x0, -2048  -> x2 = 0xFFFFF800 (max-magnitude negative imm)
            memory[1] = 32'h80000113;
            //  sw   x1, 0(x0)
            memory[2] = 32'h00102023;
            //  sw   x2, 4(x0)
            memory[3] = 32'h00202223;
            memory[4] = 32'h0000006F;

            reset_processor();
            wait_for_pc(32'd16, 300);
            check_result(32'h00000000, 32'hFFFFFFFF, "ADDI -1 -> 0xFFFFFFFF");
            check_result(32'h00000004, 32'hFFFFF800, "ADDI -2048 -> 0xFFFFF800");
        end
    endtask

    // ============================================================
    // TEST 41 – Loop: sum 1..10 using BLT
    // ============================================================
    task test_loop_sum;
        begin
            test_num = 41;
            $display("\n========================================");
            $display("Test 41: Loop sum 1..10 using BLT");
            $display("========================================");
            init_memory();
            //  addi x1, x0, 0    (sum)
            memory[0] = 32'h00000093;
            //  addi x2, x0, 1    (i)
            memory[1] = 32'h00100113;
            //  addi x3, x0, 11   (limit)
            memory[2] = 32'h00B00193;
            // LOOP: add  x1, x1, x2  (sum += i)    addr 12
            memory[3] = 32'h002080B3;
            //  addi x2, x2, 1   (i++)
            memory[4] = 32'h00110113;
            //  blt  x2, x3, -8  (if i < 11 loop)
            memory[5] = 32'hFE314CE3;
            //  sw   x1, 0(x0)
            memory[6] = 32'h00102023;
            memory[7] = 32'h0000006F;

            reset_processor();
            wait_for_pc(32'd28, 600);
            check_result(32'h00000000, 32'h00000037, "Loop sum 1..10 = 55 (0x37)");
        end
    endtask

    // ============================================================
    // TEST 42 – Store/Load round-trip (SW then LW)
    // ============================================================
    task test_store_load_roundtrip;
        begin
            test_num = 42;
            $display("\n========================================");
            $display("Test 42: SW then LW round-trip");
            $display("========================================");
            init_memory();
            //  addi x1, x0, 0x300
            memory[0] = 32'h30000093;
            //  lui  x2, 0x12345     -> x2 = 0x12345000
            memory[1] = 32'h12345137;
            //  addi x2, x2, 0x678  -> x2 = 0x12345678 (bit11=0, positive)
            memory[2] = 32'h67810113;
            //  sw   x2, 0(x1)
            memory[3] = 32'h0020A023;
            //  lw   x3, 0(x1)       -> x3 = 0x12345678
            memory[4] = 32'h0000A183;
            //  sw   x3, 0(x0)
            memory[5] = 32'h00302023;
            memory[6] = 32'h0000006F;

            reset_processor();
            wait_for_pc(32'd24, 300);
            check_result(32'h00000000, 32'h12345678, "SW+LW round-trip: 0x12345678");
        end
    endtask

    // ============================================================
    // TEST 43 – SB/SH partial store then LW readback
    // ============================================================
    task test_partial_stores;
        begin
            test_num = 43;
            $display("\n========================================");
            $display("Test 43: SB + SH partial stores, LW readback");
            $display("========================================");
            init_memory();
            memory[64] = 32'h00000000; // zero out target addr 0x100
            //  addi x1, x0, 0x100
            memory[0] = 32'h10000093;
            //  addi x2, x0, 0xAB
            memory[1] = 32'h0AB00113;
            //  lui  x3, 1           -> x3 = 0x00001000
            memory[2] = 32'h000011B7;
            //  ori  x3, x3, 0x234  -> x3 = 0x00001234
            memory[3] = 32'h2341E193;
            //  sb   x2, 0(x1)       -> byte 0 = 0xAB at addr 0x100
            memory[4] = 32'h00208023;
            //  sh   x3, 2(x1)       -> half at byte-offset 2 = 0x1234 at addr 0x102
            memory[5] = 32'h00309123;
            //  lw   x4, 0(x1)       -> full word: 0x12340000 | 0x000000AB = 0x123400AB
            memory[6] = 32'h0000A203;
            //  sw   x4, 0(x0)
            memory[7] = 32'h00402023;
            memory[8] = 32'h0000006F;

            reset_processor();
            wait_for_pc(32'd36, 400);
            check_result(32'h00000000, 32'h123400AB, "SB byte0=0xAB, SH upper=0x1234");
        end
    endtask

    // ============================================================
    // TEST 44 – JALR with non-zero offset (LSB clearing)
    // ============================================================
    task test_jalr_lsb_clear;
        begin
            test_num = 44;
            $display("\n========================================");
            $display("Test 44: JALR LSB cleared on target");
            $display("========================================");
            init_memory();
            //  addi x1, x0, 25   -> x1 = 25 (odd addr)
            memory[0] = 32'h01900093;
            //  jalr x2, x1, 0   -> target = 25 & ~1 = 24, x2 = PC+4 = 8
            memory[1] = 32'h00008167;
            //  addi x3, x0, 99  -> addr 8 SKIPPED
            memory[2] = 32'h06300193;
            //  nop addr 12
            memory[3] = 32'h00000013;
            //  nop addr 16
            memory[4] = 32'h00000013;
            //  nop addr 20
            memory[5] = 32'h00000013;
            //  addi x3, x0, 7   -> addr 24 (where JALR lands)
            memory[6] = 32'h00700193;
            //  sw   x2, 0(x0)
            memory[7] = 32'h00202023;
            //  sw   x3, 4(x0)
            memory[8] = 32'h00302223;
            memory[9] = 32'h0000006F;

            reset_processor();
            wait_for_pc(32'd36, 300);
            check_result(32'h00000000, 32'h00000008, "JALR LSB: link=8");
            check_result(32'h00000004, 32'h00000007, "JALR LSB: landed at 24 (25 & ~1)");
        end
    endtask

    // ============================================================
    // MAIN
    // ============================================================
    initial begin
        $display("========================================");
        $display("  Full RV32I Testbench");
        $display("  Every instruction individually tested");
        $display("========================================");

        passed_tests = 0;
        total_tests  = 0;
        test_num     = 0;

        // R-type
        test_add();
        test_sub();
        test_xor();
        test_or();
        test_and();
        test_sll();
        test_srl();
        test_sra();
        test_slt();
        test_sltu();

        // I-type ALU
        test_addi();
        test_xori();
        test_ori();
        test_andi();
        test_slli();
        test_srli();
        test_srai();
        test_slti();
        test_sltiu();

        // Load
        test_lw();
        test_lh();
        test_lb();
        test_lbu();
        test_lhu();

        // Store
        test_sw();
        test_sh();
        test_sb();

        // Branch
        test_beq();
        test_bne();
        test_blt();
        test_bge();
        test_bltu();
        test_bgeu();

        // Jump
        test_jal();
        test_jalr();

        // Upper immediate
        test_lui();
        test_auipc();

        // Combo / edge cases
        test_lui_addi_combo();
        test_x0_hardwired_zero();
        test_negative_imm();
        test_loop_sum();
        test_store_load_roundtrip();
        test_partial_stores();
        test_jalr_lsb_clear();

        $display("\n========================================");
        $display("  TEST SUMMARY");
        $display("========================================");
        $display("Passed : %0d / %0d", passed_tests, total_tests);
        $display("Score  : %0d%%", (passed_tests * 100) / total_tests);
        $display("========================================\n");

        if (passed_tests == total_tests)
            $display("*** ALL TESTS PASSED ***");
        else
            $display("*** SOME TESTS FAILED – see [FAIL] lines above ***");

        $finish;
    end

    // Global timeout
    initial begin
        #5000000;
        $display("\n[ERROR] Simulation timeout");
        $display("Passed %0d / %0d before timeout", passed_tests, total_tests);
        $finish;
    end

endmodule
