`timescale 1ns/1ps

module riscv_tb_24112083_hard;
    reg clk, reset;
    wire [31:0] mem_addr, mem_wdata, mem_rdata;
    wire [3:0] mem_wmask;
    wire mem_rstrb;
    reg mem_rbusy, mem_wbusy;

    reg [31:0] memory [0:4095];
    reg [31:0] read_data;
    integer test_num, passed, total;

    riscv_processor uut (
        .clk(clk), .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_wmask(mem_wmask),
        .mem_rdata(mem_rdata), .mem_rstrb(mem_rstrb), .mem_rbusy(mem_rbusy),
        .mem_wbusy(mem_wbusy), .reset(reset)
    );

    initial begin clk = 0; forever #5 clk = ~clk; end
    always @(posedge clk) if (mem_rstrb) read_data <= memory[mem_addr[31:2]];
    assign mem_rdata = read_data;
    always @(posedge clk) begin
        if (mem_wmask[0]) memory[mem_addr[31:2]][7:0]   <= mem_wdata[7:0];
        if (mem_wmask[1]) memory[mem_addr[31:2]][15:8]  <= mem_wdata[15:8];
        if (mem_wmask[2]) memory[mem_addr[31:2]][23:16] <= mem_wdata[23:16];
        if (mem_wmask[3]) memory[mem_addr[31:2]][31:24] <= mem_wdata[31:24];
    end

    task check(input [31:0] addr, input [31:0] exp, input [160:1] msg);
        begin total = total + 1;
            if (memory[addr[31:2]] === exp) begin $display("[PASS] %s", msg); passed = passed + 1; end
            else $display("[FAIL] %s | Exp: %h Got: %h", msg, exp, memory[addr[31:2]]);
        end
    endtask

    initial begin
        passed = 0; total = 0; mem_rbusy = 0; mem_wbusy = 0;
        for (integer i=0; i<4096; i=i+1) memory[i] = 32'h00000013;

        $display("========================================");
        $display("HARD TEST CASES: RV32I STRESS TEST");
        $display("========================================");

        // --- TEST 1: The "Summation Loop" (1 + 2 + 3 + 4) ---
        // Computes sum = 1+2+3+4 = 10 using BLT branch back to LOOP.
        // x1 = total sum, x2 = counter, x3 = limit (5)
        // LOOP is at byte 0x0C (word 3). Branch is at byte 0x14 (word 5).
        // Required BLT offset = 0x0C - 0x14 = -8  =>  encoding: 0xFE314CE3
        // (was 0xF6314CE3 which encoded offset -20, branching to 0x00 -- BUG FIXED)
        memory[0] = 32'h00000093; // addi x1, x0, 0   (li x1, 0)
        memory[1] = 32'h00100113; // addi x2, x0, 1   (li x2, 1)
        memory[2] = 32'h00500193; // addi x3, x0, 5   (li x3, 5)
        memory[3] = 32'h002080B3; // LOOP: add x1, x1, x2
        memory[4] = 32'h00110113; // addi x2, x2, 1
        memory[5] = 32'hFE314CE3; // blt x2, x3, LOOP  (offset = -8, target = 0x0C)
        memory[6] = 32'h00102023; // sw x1, 0(x0)
        memory[7] = 32'h0000006F; // jal x0, 0  (spin)

        reset = 0; #20; reset = 1; #2000;
        check(32'h0, 32'd10, "Summation Loop (1+2+3+4)");

        // --- TEST 2: JALR Indirect Chain ---
        // Flow: [0x00] li x1,16 -> [0x04] jalr x2,0(x1)  -> jumps to 0x10
        //       [0x10] jal x0,+12                         -> jumps to 0x1C
        //       [0x1C] jal x0,-20                         -> jumps to 0x08
        //       [0x08] sw x2,64(x0)                       -> stores 8 to byte 0x40 (word 16)
        //       [0x0C] spin
        //
        // x2 = PC+4 = 0x08 after the JALR at 0x04.
        // Return JAL at 0x1C must reach sw at 0x08: offset = 0x08 - 0x1C = -20
        //   correct encoding: 0xFEDFF06F
        //   (0xFEC0006F was wrong -- it decodes to -1046548, not -20 -- BUG FIXED)
        //
        // sw target is byte 0x40 (word 16) to avoid overwriting instruction memory[0].
        //   sw x2, 64(x0) = 0x04202023  (was sw x2, 0(x0) which clobbered memory[0])
        for (integer i=0; i<4096; i=i+1) memory[i] = 32'h00000013;
        memory[0]  = 32'h01000093; // addi x1, x0, 16   (li x1, 16)
        memory[1]  = 32'h00008167; // jalr x2, 0(x1)    (jump to x1=0x10, x2=link=0x08)
        memory[2]  = 32'h04202023; // sw x2, 64(x0)     (reached on return; stores 8 to 0x40)
        memory[3]  = 32'h0000006F; // jal x0, 0         (spin)
        memory[4]  = 32'h00C0006F; // jal x0, +12       (0x10 -> 0x1C)
        memory[7]  = 32'hFEDFF06F; // jal x0, -20       (0x1C -> 0x08, the sw)

        reset = 0; #20; reset = 1; #1500;
        check(32'h40, 32'h8, "JALR Chain + Link Reg");

        // --- TEST 3: Signed Comparison Torture ---
        // Tests SLT with INT_MIN and INT_MAX.
        // INT_MIN = 0x80000000  via: lui x1, 0x80000
        // INT_MAX = 0x7FFFFFFF  via: lui x2, 0x80000  then  addi x2, x2, -1
        //   (0x80000000 + 0xFFF...FFFF = 0x7FFFFFFF)
        //   (was lui x2,0x7FFFF / addi -1 = 0x7FFFEFFF, not INT_MAX -- BUG FIXED)
        for (integer i=0; i<4096; i=i+1) memory[i] = 32'h00000013;
        memory[0] = 32'h800000B7; // lui  x1, 0x80000          (x1 = 0x80000000 = INT_MIN)
        memory[1] = 32'h80000137; // lui  x2, 0x80000          (x2 = 0x80000000)
        memory[2] = 32'hFFF10113; // addi x2, x2, -1           (x2 = 0x7FFFFFFF = INT_MAX)
        memory[3] = 32'h0020A1B3; // slt  x3, x1, x2           (x3 = 1: INT_MIN < INT_MAX)
        memory[4] = 32'h001121B3; // slt  x3, x2, x1           (x3 = 0: INT_MAX not < INT_MIN)
        memory[5] = 32'h00302023; // sw   x3, 0(x0)            (store 0)

        reset = 0; #20; reset = 1; #1000;
        check(32'h0, 32'h0, "Signed SLT: MaxInt < MinInt is FALSE");

        // ─────────────────────────────────────────────────────────────────
        // TEST 4: Byte / halfword load-store (SB, LBU, SH, LHU)
        // ─────────────────────────────────────────────────────────────────
        // Build word 0x04030201 at scratch base x1=0x80.
        // lbu byte-0 => 0x01, lbu byte-1 => 0x02, lhu half-0 => 0x0201.
        // Patch byte-1 with SB 0xFF, then LW => 0x0403FF01.
        // All results stored relative to x1 to keep clear of the code area.
        //   code: words 0-14 (bytes 0x00-0x38)
        //   data: x1+0=0x80 (source word), x1+4..+16 = results
        for (integer i=0; i<4096; i=i+1) memory[i] = 32'h00000013;
        memory[ 0] = 32'h08000093; // addi x1,x0,128       (x1 = 0x80)
        memory[ 1] = 32'h04030137; // lui  x2,0x04030       (x2 = 0x04030000)
        memory[ 2] = 32'h20110113; // addi x2,x2,0x201      (x2 = 0x04030201)
        memory[ 3] = 32'h0020A023; // sw   x2,0(x1)         (mem[0x80] = 0x04030201)
        memory[ 4] = 32'h0000C183; // lbu  x3,0(x1)         (x3 = 0x01)
        memory[ 5] = 32'h0030A223; // sw   x3,4(x1)         (mem[0x84] = 0x01)
        memory[ 6] = 32'h0010C183; // lbu  x3,1(x1)         (x3 = 0x02)
        memory[ 7] = 32'h0030A423; // sw   x3,8(x1)         (mem[0x88] = 0x02)
        memory[ 8] = 32'h0000D183; // lhu  x3,0(x1)         (x3 = 0x0201)
        memory[ 9] = 32'h0030A623; // sw   x3,12(x1)        (mem[0x8C] = 0x0201)
        memory[10] = 32'h0FF00213; // addi x4,x0,0xFF       (x4 low-byte = 0xFF)
        memory[11] = 32'h004080A3; // sb   x4,1(x1)         (mem[0x81] = 0xFF)
        memory[12] = 32'h0000A283; // lw   x5,0(x1)         (x5 = 0x0403FF01)
        memory[13] = 32'h0050A823; // sw   x5,16(x1)        (mem[0x90] = 0x0403FF01)
        memory[14] = 32'h0000006F; // jal  x0,0             (spin)

        reset = 0; #20; reset = 1; #2000;
        check(32'h84, 32'h00000001, "LBU byte 0 of 0x04030201");
        check(32'h88, 32'h00000002, "LBU byte 1 of 0x04030201");
        check(32'h8C, 32'h00000201, "LHU low half of 0x04030201");
        check(32'h90, 32'h0403FF01, "LW after SB patch of byte 1");

        // ─────────────────────────────────────────────────────────────────
        // TEST 5: All six shift instructions on 0x80000001
        // ─────────────────────────────────────────────────────────────────
        // x1 = 0x80000001 (MSB + LSB set — stresses both directions).
        //   sll  x1,x2(=1) => 0x00000002  (MSB lost)
        //   srl  x1,x2(=1) => 0x40000000  (logical: zero-fill)
        //   sra  x1,x2(=1) => 0xC0000000  (arithmetic: sign-fill)
        //   slli x1,4      => 0x00000010
        //   srli x1,4      => 0x08000000
        //   srai x1,4      => 0xF8000000
        // Results stored to 0x40-0x54 (code ends at word 15 = 0x3C).
        for (integer i=0; i<4096; i=i+1) memory[i] = 32'h00000013;
        memory[ 0] = 32'h800000B7; // lui  x1,0x80000       (x1 = 0x80000000)
        memory[ 1] = 32'h0010E093; // ori  x1,x1,1          (x1 = 0x80000001)
        memory[ 2] = 32'h00100113; // addi x2,x0,1          (shift amount = 1)
        memory[ 3] = 32'h002091B3; // sll  x3,x1,x2         (x3 = 0x00000002)
        memory[ 4] = 32'h0020D233; // srl  x4,x1,x2         (x4 = 0x40000000)
        memory[ 5] = 32'h4020D2B3; // sra  x5,x1,x2         (x5 = 0xC0000000)
        memory[ 6] = 32'h00409313; // slli x6,x1,4          (x6 = 0x00000010)
        memory[ 7] = 32'h0040D393; // srli x7,x1,4          (x7 = 0x08000000)
        memory[ 8] = 32'h4040D413; // srai x8,x1,4          (x8 = 0xF8000000)
        memory[ 9] = 32'h04302023; // sw   x3,64(x0)
        memory[10] = 32'h04402223; // sw   x4,68(x0)
        memory[11] = 32'h04502423; // sw   x5,72(x0)
        memory[12] = 32'h04602623; // sw   x6,76(x0)
        memory[13] = 32'h04702823; // sw   x7,80(x0)
        memory[14] = 32'h04802A23; // sw   x8,84(x0)
        memory[15] = 32'h0000006F; // jal  x0,0             (spin)

        reset = 0; #20; reset = 1; #2000;
        check(32'h40, 32'h00000002, "SLL  0x80000001 << 1");
        check(32'h44, 32'h40000000, "SRL  0x80000001 >> 1 (logical)");
        check(32'h48, 32'hC0000000, "SRA  0x80000001 >> 1 (arithmetic)");
        check(32'h4C, 32'h00000010, "SLLI 0x80000001 << 4");
        check(32'h50, 32'h08000000, "SRLI 0x80000001 >> 4 (logical)");
        check(32'h54, 32'hF8000000, "SRAI 0x80000001 >> 4 (arithmetic)");

        // ─────────────────────────────────────────────────────────────────
        // TEST 6: Unsigned branch torture (BLTU / BGEU / BGE sign inversion)
        // ─────────────────────────────────────────────────────────────────
        // x1=0xFFFFFFFF (-1 signed, MAX unsigned), x2=1.
        //   bltu x2,x1,+8  => TAKEN   (1 <u 0xFFFFFFFF)       => store 1
        //   bgeu x1,x2,+8  => TAKEN   (0xFFFFFFFF >=u 1)      => store 1
        //   bge  x1,x2,+8  => NOT taken (-1 >=s 1 is FALSE)       => store 0
        //   BGE rs1,rs2 branches if rs1 >= rs2 signed.
        //   rs1=x1=-1, rs2=x2=1: -1 >= 1 is FALSE => not taken => x3=0.
        //   (Old encoding had bge x2,x1 = "1 >= -1" = TRUE => was incorrectly taken.)
        for (integer i=0; i<4096; i=i+1) memory[i] = 32'h00000013;
        memory[ 0] = 32'hFFF00093; // addi x1,x0,-1         (x1 = 0xFFFFFFFF)
        memory[ 1] = 32'h00100113; // addi x2,x0,1          (x2 = 1)
        memory[ 2] = 32'h00100193; // addi x3,x0,1          (result init = 1)
        memory[ 3] = 32'h00116463; // bltu x2,x1,+8         (taken -> word 5)
        memory[ 4] = 32'h00000193; // addi x3,x0,0          (skipped)
        memory[ 5] = 32'h04302023; // sw   x3,64(x0)        => 1
        memory[ 6] = 32'h00100193; // addi x3,x0,1          (re-init)
        memory[ 7] = 32'h0020F463; // bgeu x1,x2,+8         (taken -> word 9)
        memory[ 8] = 32'h00000193; // addi x3,x0,0          (skipped)
        memory[ 9] = 32'h04302223; // sw   x3,68(x0)        => 1
        memory[10] = 32'h00100193; // addi x3,x0,1          (re-init)
        memory[11] = 32'h0020D463; // bge  x1,x2,+8         (NOT taken: -1 >=s 1 is FALSE)
        memory[12] = 32'h00000193; // addi x3,x0,0          (executes -> x3=0)
        memory[13] = 32'h04302423; // sw   x3,72(x0)        => 0
        memory[14] = 32'h0000006F; // jal  x0,0             (spin)

        reset = 0; #20; reset = 1; #2000;
        check(32'h40, 32'h00000001, "BLTU: 1 <u 0xFFFFFFFF => TAKEN");
        check(32'h44, 32'h00000001, "BGEU: 0xFFFFFFFF >=u 1 => TAKEN");
        check(32'h48, 32'h00000000, "BGE:  -1 >=s 1 => NOT TAKEN");

        // ─────────────────────────────────────────────────────────────────
        // TEST 7: AUIPC + XORI + AND + OR
        // ─────────────────────────────────────────────────────────────────
        // auipc x1,4 at PC=0x00  => x1 = 0x00004000
        // xori  x2,x1,-1         => x2 = ~0x4000 = 0xFFFFBFFF
        // addi  x3,x0,0xFF
        // and   x4,x2,x3         => x4 = 0xFFFFBFFF & 0xFF = 0x000000FF
        // or    x5,x2,x3         => x5 = 0xFFFFBFFF | 0xFF = 0xFFFFBFFF
        for (integer i=0; i<4096; i=i+1) memory[i] = 32'h00000013;
        memory[0] = 32'h00004097; // auipc x1,4             (x1 = PC+0x4000 = 0x4000)
        memory[1] = 32'hFFF0C113; // xori  x2,x1,-1         (x2 = 0xFFFFBFFF)
        memory[2] = 32'h0FF00193; // addi  x3,x0,0xFF
        memory[3] = 32'h00317233; // and   x4,x2,x3         (x4 = 0x000000FF)
        memory[4] = 32'h003162B3; // or    x5,x2,x3         (x5 = 0xFFFFBFFF)
        memory[5] = 32'h04102023; // sw    x1,64(x0)
        memory[6] = 32'h04402223; // sw    x4,68(x0)
        memory[7] = 32'h04502423; // sw    x5,72(x0)
        memory[8] = 32'h0000006F; // jal   x0,0             (spin)

        reset = 0; #20; reset = 1; #1500;
        check(32'h40, 32'h00004000, "AUIPC at PC=0x00 with imm=4");
        check(32'h44, 32'h000000FF, "AND (XORI result & 0xFF)");
        check(32'h48, 32'hFFFFBFFF, "OR  (XORI result | 0xFF)");

        // ─────────────────────────────────────────────────────────────────
        // TEST 8: BEQ/BNE — countdown loop and not-taken BNE
        // ─────────────────────────────────────────────────────────────────
        // Count x1 from 5 down to 0 using BNE as loop-back condition.
        // After loop x1==0; store to verify.
        // Then: x2=x3=7, BNE x2,x3 should NOT branch (x2==x3),
        // so the addi below executes and stores 1.
        //   bne x1,x0,-4  at byte 0x08: offset=-4, target=0x04 (word 1 = LOOP)
        //   bne x2,x3,+8  at byte 0x18: offset=+8, target=0x20 (word 8 = sw)
        for (integer i=0; i<4096; i=i+1) memory[i] = 32'h00000013;
        memory[0] = 32'h00500093; // addi x1,x0,5
        memory[1] = 32'hFFF08093; // LOOP: addi x1,x1,-1
        memory[2] = 32'hFE009EE3; // bne  x1,x0,-4         (->LOOP while x1!=0)
        memory[3] = 32'h04102023; // sw   x1,64(x0)        => 0
        memory[4] = 32'h00700113; // addi x2,x0,7
        memory[5] = 32'h00700193; // addi x3,x0,7
        memory[6] = 32'h00311463; // bne  x2,x3,+8         (NOT taken: x2==x3)
        memory[7] = 32'h00100213; // addi x4,x0,1          (executes)
        memory[8] = 32'h04402223; // sw   x4,68(x0)        => 1
        memory[9] = 32'h0000006F; // jal  x0,0             (spin)

        reset = 0; #20; reset = 1; #2000;
        check(32'h40, 32'h00000000, "BNE loop: x1==0 after countdown from 5");
        check(32'h44, 32'h00000001, "BNE not taken when x2==x3==7");

        // ─────────────────────────────────────────────────────────────────
        // TEST 9: SUB / SLTU / SLT / XOR
        // ─────────────────────────────────────────────────────────────────
        // sub  x3,x1(10),x2(3)   => 7
        // sltu x6,x4(-1),x5(1)   => 0  (0xFFFFFFFF >=u 1)
        // sltu x7,x5(1),x4(-1)   => 1  (1 <u 0xFFFFFFFF)
        // slt  x8,x4(-1),x5(1)   => 1  (-1 <s 1)
        // xor  x9,x1(10),x2(3)   => 9  (1010 ^ 0011)
        for (integer i=0; i<4096; i=i+1) memory[i] = 32'h00000013;
        memory[ 0] = 32'h00A00093; // addi x1,x0,10
        memory[ 1] = 32'h00300113; // addi x2,x0,3
        memory[ 2] = 32'h402081B3; // sub  x3,x1,x2         (x3 = 7)
        memory[ 3] = 32'hFFF00213; // addi x4,x0,-1         (x4 = 0xFFFFFFFF)
        memory[ 4] = 32'h00100293; // addi x5,x0,1
        memory[ 5] = 32'h00523333; // sltu x6,x4,x5         (x6 = 0)
        memory[ 6] = 32'h0042B3B3; // sltu x7,x5,x4         (x7 = 1)
        memory[ 7] = 32'h00522433; // slt  x8,x4,x5         (x8 = 1)
        memory[ 8] = 32'h0020C4B3; // xor  x9,x1,x2         (x9 = 9)
        memory[ 9] = 32'h04302023; // sw   x3,64(x0)        => 7
        memory[10] = 32'h04602223; // sw   x6,68(x0)        => 0
        memory[11] = 32'h04702423; // sw   x7,72(x0)        => 1
        memory[12] = 32'h04802623; // sw   x8,76(x0)        => 1
        memory[13] = 32'h04902823; // sw   x9,80(x0)        => 9
        memory[14] = 32'h0000006F; // jal  x0,0             (spin)

        reset = 0; #20; reset = 1; #2000;
        check(32'h40, 32'h00000007, "SUB  10 - 3");
        check(32'h44, 32'h00000000, "SLTU 0xFFFFFFFF <u 1 => FALSE");
        check(32'h48, 32'h00000001, "SLTU 1 <u 0xFFFFFFFF => TRUE");
        check(32'h4C, 32'h00000001, "SLT  -1 <s 1 => TRUE");
        check(32'h50, 32'h00000009, "XOR  10 ^ 3");

        $display("\n========================================");
        $display("HARD TEST SUMMARY: %0d/%0d PASSED", passed, total);
        $display("========================================\n");
        $finish;
    end
endmodule