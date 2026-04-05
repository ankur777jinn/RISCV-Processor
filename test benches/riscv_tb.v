// =============================================================================
// Comprehensive RISC-V RV32I Testbench
// Tests all 37 RV32I instructions (except ecall/ebreak)
// =============================================================================

`timescale 1ns/1ps

module riscv_tb;

    // =========================================================================
    // Signals
    // =========================================================================
    reg         clk;
    reg         reset;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [3:0]  mem_wmask;
    wire [31:0] mem_rdata;
    wire        mem_rstrb;
    reg         mem_rbusy;
    reg         mem_wbusy;

    // =========================================================================
    // Memory — 16 KB (4096 words)
    // =========================================================================
    reg [31:0] mem [0:4095];
    reg [31:0] rd_reg;

    always @(posedge clk) begin
        if (mem_rstrb)
            rd_reg <= mem[mem_addr[31:2]];
    end
    assign mem_rdata = rd_reg;

    always @(posedge clk) begin
        if (mem_wmask[0]) mem[mem_addr[31:2]][7:0]   <= mem_wdata[7:0];
        if (mem_wmask[1]) mem[mem_addr[31:2]][15:8]  <= mem_wdata[15:8];
        if (mem_wmask[2]) mem[mem_addr[31:2]][23:16] <= mem_wdata[23:16];
        if (mem_wmask[3]) mem[mem_addr[31:2]][31:24] <= mem_wdata[31:24];
    end

    always @(*) begin
        mem_rbusy = 0;
        mem_wbusy = 0;
    end

    // =========================================================================
    // DUT
    // =========================================================================
    riscv_processor #(
        .RESET_ADDR(32'h00000000),
        .ADDR_WIDTH(32)
    ) dut (
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

    // =========================================================================
    // Clock — 100 MHz (10 ns period)
    // =========================================================================
    initial clk = 0;
    always #5 clk = ~clk;

    // =========================================================================
    // Counters
    // =========================================================================
    integer pass_cnt, fail_cnt, total_cnt, i;

    // =========================================================================
    // Helper tasks
    // =========================================================================
    task clear_mem;
        begin
            for (i = 0; i < 4096; i = i + 1)
                mem[i] = 32'h00000013;  // NOP (addi x0,x0,0)
        end
    endtask

    task do_reset;
        begin
            reset = 0;
            @(posedge clk); @(posedge clk);
            reset = 1;
        end
    endtask

    task run_n;
        input integer n;
        integer c;
        begin
            for (c = 0; c < n; c = c + 1)
                @(posedge clk);
        end
    endtask

    task halt_at;
        input [31:0] target;
        input integer limit;
        integer c;
        begin
            for (c = 0; c < limit; c = c + 1) begin
                @(posedge clk);
                if (mem_addr == target && mem_rstrb)
                    c = limit;
            end
        end
    endtask

    task check;
        input [31:0] addr;
        input [31:0] expected;
        input [255:0] label;
        begin
            total_cnt = total_cnt + 1;
            if (mem[addr[31:2]] === expected) begin
                $display("  [PASS] %0s — got 0x%08h", label, mem[addr[31:2]]);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  [FAIL] %0s — expected 0x%08h, got 0x%08h",
                         label, expected, mem[addr[31:2]]);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    // =========================================================================
    // Test programs
    // =========================================================================

    // ----- Test 1: ADD, SUB, ADDI -----
    task test_arithmetic;
        begin
            $display("\n--- Test 1: ADD / SUB / ADDI ---");
            clear_mem();
            mem[0] = 32'h00500093;  // addi x1, x0, 5
            mem[1] = 32'h00300113;  // addi x2, x0, 3
            mem[2] = 32'h002081B3;  // add  x3, x1, x2       => 8
            mem[3] = 32'h40208233;  // sub  x4, x1, x2       => 2
            mem[4] = 32'hFFE08293;  // addi x5, x1, -2       => 3
            mem[5] = 32'h00302023;  // sw   x3, 0(x0)
            mem[6] = 32'h00402223;  // sw   x4, 4(x0)
            mem[7] = 32'h00502423;  // sw   x5, 8(x0)
            mem[8] = 32'h0200006F;  // jal  x0, 32 (halt)
            do_reset();
            halt_at(32'd32, 300);
            check(32'h0, 32'h00000008, "ADD 5+3=8");
            check(32'h4, 32'h00000002, "SUB 5-3=2");
            check(32'h8, 32'h00000003, "ADDI 5+(-2)=3");
        end
    endtask

    // ----- Test 2: AND, OR, XOR, ANDI, ORI, XORI -----
    task test_logical;
        begin
            $display("\n--- Test 2: AND / OR / XOR + immediates ---");
            clear_mem();
            mem[0] = 32'h0FF00093;  // addi x1, x0, 0xFF
            mem[1] = 32'h0F000113;  // addi x2, x0, 0xF0
            mem[2] = 32'h0020F1B3;  // and  x3, x1, x2       => 0xF0
            mem[3] = 32'h0020E233;  // or   x4, x1, x2       => 0xFF
            mem[4] = 32'h0020C2B3;  // xor  x5, x1, x2       => 0x0F
            mem[5] = 32'h0AA0F313;  // andi x6, x1, 0x0AA    => 0xAA
            mem[6] = 32'h0AA0E393;  // ori  x7, x1, 0x0AA    => 0xFF
            mem[7] = 32'h0020C413;  // xori x8, x1, 2        => 0xFD
            mem[8]  = 32'h00302023;  // sw x3,  0(x0)
            mem[9]  = 32'h00402223;  // sw x4,  4(x0)
            mem[10] = 32'h00502423;  // sw x5,  8(x0)
            mem[11] = 32'h00602623;  // sw x6, 12(x0)
            mem[12] = 32'h00702823;  // sw x7, 16(x0)
            mem[13] = 32'h00802A23;  // sw x8, 20(x0)
            mem[14] = 32'h0380006F;  // jal  x0, 56 (halt)
            do_reset();
            halt_at(32'd56, 400);
            check(32'h00, 32'h000000F0, "AND");
            check(32'h04, 32'h000000FF, "OR");
            check(32'h08, 32'h0000000F, "XOR");
            check(32'h0C, 32'h000000AA, "ANDI");
            check(32'h10, 32'h000000FF, "ORI");
            check(32'h14, 32'h000000FD, "XORI");
        end
    endtask

    // ----- Test 3: SLL, SRL, SRA, SLLI, SRLI, SRAI -----
    task test_shifts;
        begin
            $display("\n--- Test 3: Shifts ---");
            clear_mem();
            mem[0] = 32'h00800093;  // addi x1, x0, 8
            mem[1] = 32'h00200113;  // addi x2, x0, 2
            mem[2] = 32'h002091B3;  // sll  x3, x1, x2       => 32
            mem[3] = 32'h0020D233;  // srl  x4, x1, x2       => 2
            // SRA with a negative number
            mem[4] = 32'hFF000293;  // addi x5, x0, -16      => 0xFFFFFFF0
            mem[5] = 32'h4020D333;  // sra  x6, x1, x2       => 2 (positive, same as SRL)
            mem[6] = 32'h4022D393;  // srai x7, x5, 2        => 0xFFFFFFFC (-4)
            // Immediate shifts
            mem[7]  = 32'h00309413;  // slli x8, x1, 3       => 64
            mem[8]  = 32'h0020D493;  // srli x9, x1, 2       => 2
            mem[9]  = 32'h00302023;  // sw x3,  0(x0)
            mem[10] = 32'h00402223;  // sw x4,  4(x0)
            mem[11] = 32'h00602423;  // sw x6,  8(x0)
            mem[12] = 32'h00702623;  // sw x7, 12(x0)
            mem[13] = 32'h00802823;  // sw x8, 16(x0)
            mem[14] = 32'h00902A23;  // sw x9, 20(x0)
            mem[15] = 32'h03C0006F;  // jal  x0, 60 (halt)
            do_reset();
            halt_at(32'd60, 500);
            check(32'h00, 32'h00000020, "SLL 8<<2=32");
            check(32'h04, 32'h00000002, "SRL 8>>2=2");
            check(32'h08, 32'h00000002, "SRA 8>>>2=2");
            check(32'h0C, 32'hFFFFFFFC, "SRAI -16>>>2=-4");
            check(32'h10, 32'h00000040, "SLLI 8<<3=64");
            check(32'h14, 32'h00000002, "SRLI 8>>2=2");
        end
    endtask

    // ----- Test 4: SLT, SLTU, SLTI, SLTIU -----
    task test_slt;
        begin
            $display("\n--- Test 4: SLT / SLTU / SLTI / SLTIU ---");
            clear_mem();
            mem[0] = 32'h00500093;  // addi x1, x0, 5
            mem[1] = 32'h00A00113;  // addi x2, x0, 10
            mem[2] = 32'h0020A1B3;  // slt  x3, x1, x2       => 1 (5<10)
            mem[3] = 32'h0010A233;  // slt  x4, x2, x1       => 0 (10<5 false)
            mem[4] = 32'h0020B2B3;  // sltu x5, x1, x2       => 1
            mem[5] = 32'h00A0A313;  // slti x6, x1, 10       => 1
            mem[6] = 32'h0010B393;  // sltiu x7, x1, 1       => 0 (5<1 false)
            mem[7]  = 32'h00302023;  // sw x3,  0(x0)
            mem[8]  = 32'h00402223;  // sw x4,  4(x0)
            mem[9]  = 32'h00502423;  // sw x5,  8(x0)
            mem[10] = 32'h00602623;  // sw x6, 12(x0)
            mem[11] = 32'h00702823;  // sw x7, 16(x0)
            mem[12] = 32'h0300006F;  // jal  x0, 48 (halt)
            do_reset();
            halt_at(32'd48, 400);
            check(32'h00, 32'h00000001, "SLT 5<10=1");
            check(32'h04, 32'h00000000, "SLT 10<5=0");
            check(32'h08, 32'h00000001, "SLTU 5<10=1");
            check(32'h0C, 32'h00000001, "SLTI 5<10=1");
            check(32'h10, 32'h00000000, "SLTIU 5<1=0");
        end
    endtask

    // ----- Test 5: LUI and AUIPC -----
    task test_upper;
        begin
            $display("\n--- Test 5: LUI / AUIPC ---");
            clear_mem();
            mem[0] = 32'h123450B7;  // lui   x1, 0x12345     => 0x12345000
            mem[1] = 32'h67808093;  // addi  x1, x1, 0x678   => 0x12345678
            mem[2] = 32'hDEADC137;  // lui   x2, 0xDEADC     => 0xDEADC000
            mem[3] = 32'h00000197;  // auipc x3, 0           => PC=12 = 0x0C
            mem[4] = 32'h00102023;  // sw x1, 0(x0)
            mem[5] = 32'h00202223;  // sw x2, 4(x0)
            mem[6] = 32'h00302423;  // sw x3, 8(x0)
            mem[7] = 32'h01C0006F;  // jal  x0, 28 (halt)
            do_reset();
            halt_at(32'd28, 300);
            check(32'h00, 32'h12345678, "LUI+ADDI = 0x12345678");
            check(32'h04, 32'hDEADC000, "LUI = 0xDEADC000");
            check(32'h08, 32'h0000000C, "AUIPC at PC=12");
        end
    endtask

    // ----- Test 6: JAL and JALR -----
    task test_jumps;
        begin
            $display("\n--- Test 6: JAL / JALR ---");
            clear_mem();
            // JAL: jump forward 12 bytes (to addr 12), save return in x1
            mem[0] = 32'h00C000EF;  // jal  x1, 12    => x1 = 4, jump to addr 12
            mem[1] = 32'h00000013;  // nop (skipped)
            mem[2] = 32'h00000013;  // nop (skipped)
            // addr 12: JALR test
            mem[3] = 32'h01C00113;  // addi x2, x0, 28  (target addr for jalr)
            mem[4] = 32'h000100E7;  // jalr x1, 0(x2)   => x1 = 20, jump to 28
            mem[5] = 32'h00000013;  // nop (skipped)
            mem[6] = 32'h00000013;  // nop (skipped)
            // addr 28:
            mem[7] = 32'h00102023;  // sw x1, 0(x0)     => save return addr (20)
            mem[8] = 32'h0240006F;  // jal  x0, 36 (halt at 64 - wait, let me recalc)
            // halt: PC should be stuck at addr 36
            // Actually, jal x0, offset. At addr 32, want jal to self. offset = 0 → infinite loop
            // Let me fix: instruction at word 8 (addr 32). Jump to addr 36.
            // 36-32=4? no, let me just do jump to self: 32'h0000006F = jal x0, 0
            mem[8] = 32'h0000006F;  // jal x0, 0 (halt = infinite loop at addr 32)
            do_reset();
            halt_at(32'd32, 300);
            check(32'h00, 32'h00000014, "JALR saved return addr 20 (0x14)");
        end
    endtask

    // ----- Test 7: All branches -----
    task test_branches;
        begin
            $display("\n--- Test 7: Branch instructions ---");
            clear_mem();
            mem[0]  = 32'h00500093;  // addi x1, x0, 5
            mem[1]  = 32'h00500113;  // addi x2, x0, 5
            mem[2]  = 32'h00300193;  // addi x3, x0, 3
            // BEQ x1,x2 → taken (5==5), skip next 2 instrs 
            mem[3]  = 32'h00208463;  // beq  x1, x2, +8  (to addr 20)
            mem[4]  = 32'h06300213;  // addi x4, x0, 99  (skipped)
            // addr 20:
            mem[5]  = 32'h02A00213;  // addi x4, x0, 42  (executed)
            // BNE x1,x3 → taken (5!=3), skip next
            mem[6]  = 32'h00309463;  // bne  x1, x3, +8  (to addr 32)
            mem[7]  = 32'h06300293;  // addi x5, x0, 99  (skipped)
            // addr 32:
            mem[8]  = 32'h03700293;  // addi x5, x0, 55  (executed)
            // BLT x1,x3 → NOT taken (5<3 false)
            mem[9]  = 32'h0030C463;  // blt  x1, x3, +8
            mem[10] = 32'h01E00313;  // addi x6, x0, 30  (executed, not skipped)
            // BGE x1,x3 → taken (5>=3)
            mem[11] = 32'h00000013;  // nop
            mem[12] = 32'h0030D463;  // bge  x1, x3, +8  (to addr 56)
            mem[13] = 32'h06300393;  // addi x7, x0, 99  (skipped)
            // addr 56:
            mem[14] = 32'h00B00393;  // addi x7, x0, 11  (executed)
            // Store results
            mem[15] = 32'h00402023;  // sw x4,  0(x0)
            mem[16] = 32'h00502223;  // sw x5,  4(x0)
            mem[17] = 32'h00602423;  // sw x6,  8(x0)
            mem[18] = 32'h00702623;  // sw x7, 12(x0)
            mem[19] = 32'h0000006F;  // jal x0, 0 (halt at addr 76)
            do_reset();
            halt_at(32'd76, 500);
            check(32'h00, 32'h0000002A, "BEQ taken → x4=42");
            check(32'h04, 32'h00000037, "BNE taken → x5=55");
            check(32'h08, 32'h0000001E, "BLT not taken → x6=30");
            check(32'h0C, 32'h0000000B, "BGE taken → x7=11");
        end
    endtask

    // ----- Test 8: LW and SW -----
    task test_load_store;
        begin
            $display("\n--- Test 8: LW / SW ---");
            clear_mem();
            mem[256] = 32'hDEADBEEF;
            mem[257] = 32'hCAFEBABE;
            mem[0] = 32'h40000093;  // addi x1, x0, 1024      (byte addr of word 256)
            mem[1] = 32'h0000A103;  // lw   x2, 0(x1)          => 0xDEADBEEF
            mem[2] = 32'h0040A183;  // lw   x3, 4(x1)          => 0xCAFEBABE
            mem[3] = 32'h003101B3;  // add  x3, x2, x3         => 0xA9AC79AD
            mem[4] = 32'h00302023;  // sw   x3, 0(x0)
            mem[5] = 32'h00202223;  // sw   x2, 4(x0)
            mem[6] = 32'h0180006F;  // jal x0, 24 (halt at 24)
            do_reset();
            halt_at(32'd24, 300);
            check(32'h0, 32'hA9AC79AD, "ADD after loads");
            check(32'h4, 32'hDEADBEEF, "Loaded value stored");
        end
    endtask

    // ----- Test 9: SB, SH, LB, LH, LBU, LHU -----
    task test_byte_half;
        begin
            $display("\n--- Test 9: SB / SH / LB / LH / LBU / LHU ---");
            clear_mem();
            mem[256] = 32'h00000000;  // clear target
            mem[0]  = 32'h40000093;  // addi x1, x0, 1024
            mem[1]  = 32'h0AB00113;  // addi x2, x0, 0xAB
            mem[2]  = 32'h00208023;  // sb   x2, 0(x1)     => byte 0 = 0xAB
            mem[3]  = 32'h12300113;  // addi x2, x0, 0x123
            mem[4]  = 32'h00209123;  // sh   x2, 2(x1)     => bytes 2-3 = 0x0123
            mem[5]  = 32'h0000A183;  // lw   x3, 0(x1)     => 0x012300AB
            // LB (signed byte): load byte 0 = 0xAB → sign-extend → 0xFFFFFFAB
            mem[6]  = 32'h00008203;  // lb   x4, 0(x1)
            // LBU (unsigned byte): load byte 0 = 0xAB → zero-extend → 0x000000AB
            mem[7]  = 32'h0000C283;  // lbu  x5, 0(x1)
            // LH (signed half): load bytes 2-3 = 0x0123 → sign-extend → 0x00000123
            mem[8]  = 32'h00209303;  // lh   x6, 2(x1)
            // LHU (unsigned half): same → 0x00000123
            mem[9]  = 32'h0020D383;  // lhu  x7, 2(x1)
            // Store results
            mem[10] = 32'h00302023;  // sw x3,  0(x0)
            mem[11] = 32'h00402223;  // sw x4,  4(x0)
            mem[12] = 32'h00502423;  // sw x5,  8(x0)
            mem[13] = 32'h00602623;  // sw x6, 12(x0)
            mem[14] = 32'h00702823;  // sw x7, 16(x0)
            mem[15] = 32'h0000006F;  // jal x0, 0 (halt at addr 60)
            do_reset();
            halt_at(32'd60, 400);
            check(32'h00, 32'h012300AB, "SB+SH combined");
            check(32'h04, 32'hFFFFFFAB, "LB sign-extend 0xAB");
            check(32'h08, 32'h000000AB, "LBU zero-extend 0xAB");
            check(32'h0C, 32'h00000123, "LH sign-extend 0x0123");
            check(32'h10, 32'h00000123, "LHU zero-extend 0x0123");
        end
    endtask

    // ----- Test 10: Loop (sum 1..5 = 15) -----
    task test_loop;
        begin
            $display("\n--- Test 10: Loop — sum 1 to 5 ---");
            clear_mem();
            mem[0] = 32'h00000093;  // addi x1, x0, 0   (sum = 0)
            mem[1] = 32'h00100113;  // addi x2, x0, 1   (i = 1)
            mem[2] = 32'h00600193;  // addi x3, x0, 6   (limit = 6)
            // loop body (addr 12):
            mem[3] = 32'h002080B3;  // add  x1, x1, x2  (sum += i)
            mem[4] = 32'h00110113;  // addi x2, x2, 1   (i++)
            mem[5] = 32'hFE314CE3;  // blt  x2, x3, -8  (back to addr 12)
            mem[6] = 32'h00102023;  // sw   x1, 0(x0)
            mem[7] = 32'h0000006F;  // jal  x0, 0 (halt at addr 28)
            do_reset();
            halt_at(32'd28, 500);
            check(32'h00, 32'h0000000F, "Sum 1..5 = 15");
        end
    endtask

    // ----- Test 11: BLTU / BGEU -----
    task test_unsigned_branch;
        begin
            $display("\n--- Test 11: BLTU / BGEU ---");
            clear_mem();
            mem[0] = 32'hFFF00093;  // addi x1, x0, -1    (= 0xFFFFFFFF unsigned)
            mem[1] = 32'h00100113;  // addi x2, x0, 1
            // BLTU x2, x1 → taken (1 < 0xFFFFFFFF unsigned)
            mem[2] = 32'h00116463;  // bltu x2, x1, +8     (to addr 16)
            mem[3] = 32'h06300193;  // addi x3, x0, 99     (skipped)
            // addr 16:
            mem[4] = 32'h02A00193;  // addi x3, x0, 42     (executed)
            // BGEU x1, x2 → taken (0xFFFFFFFF >= 1 unsigned)
            mem[5] = 32'h0020F463;  // bgeu x1, x2, +8     (to addr 28)
            mem[6] = 32'h06300213;  // addi x4, x0, 99     (skipped)
            // addr 28:
            mem[7]  = 32'h03700213;  // addi x4, x0, 55    (executed)
            mem[8]  = 32'h00302023;  // sw x3, 0(x0)
            mem[9]  = 32'h00402223;  // sw x4, 4(x0)
            mem[10] = 32'h0000006F;  // jal x0, 0 (halt at addr 40)
            do_reset();
            halt_at(32'd40, 400);
            check(32'h00, 32'h0000002A, "BLTU taken → x3=42");
            check(32'h04, 32'h00000037, "BGEU taken → x4=55");
        end
    endtask

    // ----- Test 12: Negative numbers -----
    task test_negatives;
        begin
            $display("\n--- Test 12: Negative number handling ---");
            clear_mem();
            mem[0] = 32'hFFB00093;  // addi x1, x0, -5     => 0xFFFFFFFB
            mem[1] = 32'hFFD00113;  // addi x2, x0, -3     => 0xFFFFFFFD
            mem[2] = 32'h002081B3;  // add  x3, x1, x2     => -8 = 0xFFFFFFF8
            mem[3] = 32'h40208233;  // sub  x4, x1, x2     => -2 = 0xFFFFFFFE
            mem[4] = 32'h00302023;  // sw x3, 0(x0)
            mem[5] = 32'h00402223;  // sw x4, 4(x0)
            mem[6] = 32'h0000006F;  // jal x0, 0 (halt)
            do_reset();
            halt_at(32'd24, 300);
            check(32'h00, 32'hFFFFFFF8, "ADD -5+(-3)=-8");
            check(32'h04, 32'hFFFFFFFE, "SUB -5-(-3)=-2");
        end
    endtask

    // =========================================================================
    // Run all tests
    // =========================================================================
    initial begin
        $display("============================================================");
        $display("     RISC-V RV32I Processor — Comprehensive Testbench");
        $display("============================================================");
        pass_cnt = 0;
        fail_cnt = 0;
        total_cnt = 0;
        mem_rbusy = 0;
        mem_wbusy = 0;

        test_arithmetic();
        test_logical();
        test_shifts();
        test_slt();
        test_upper();
        test_jumps();
        test_branches();
        test_load_store();
        test_byte_half();
        test_loop();
        test_unsigned_branch();
        test_negatives();

        $display("\n============================================================");
        $display("  RESULTS:  %0d / %0d passed", pass_cnt, total_cnt);
        if (fail_cnt == 0)
            $display("  >>> ALL TESTS PASSED <<<");
        else
            $display("  >>> %0d TESTS FAILED <<<", fail_cnt);
        $display("============================================================\n");
        $finish;
    end

    // Watchdog
    initial begin
        #800000;
        $display("\n[TIMEOUT] Simulation exceeded 800 us");
        $finish;
    end

endmodule
