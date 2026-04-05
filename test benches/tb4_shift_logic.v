// =============================================================================
// Testbench 4: Shift and Bitwise Logic
// Tests SLL, SRL, SRA, SLLI, SRLI, SRAI, AND, OR, XOR, ANDI, ORI, XORI
// =============================================================================

`timescale 1ns/1ps

module tb4_shift_logic;

    reg clk, reset;
    wire [31:0] mem_addr, mem_wdata;
    wire [3:0] mem_wmask;
    wire [31:0] mem_rdata;
    wire mem_rstrb;
    reg mem_rbusy, mem_wbusy;
    reg [31:0] mem [0:4095];
    reg [31:0] rd_reg;
    integer pass_cnt, fail_cnt, total_cnt, i;

    always @(posedge clk) if (mem_rstrb) rd_reg <= mem[mem_addr[31:2]];
    assign mem_rdata = rd_reg;
    always @(posedge clk) begin
        if (mem_wmask[0]) mem[mem_addr[31:2]][7:0]   <= mem_wdata[7:0];
        if (mem_wmask[1]) mem[mem_addr[31:2]][15:8]  <= mem_wdata[15:8];
        if (mem_wmask[2]) mem[mem_addr[31:2]][23:16] <= mem_wdata[23:16];
        if (mem_wmask[3]) mem[mem_addr[31:2]][31:24] <= mem_wdata[31:24];
    end
    always @(*) begin mem_rbusy = 0; mem_wbusy = 0; end

    riscv_processor #(.RESET_ADDR(0)) dut (
        .clk(clk), .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_wmask(mem_wmask), .mem_rdata(mem_rdata), .mem_rstrb(mem_rstrb),
        .mem_rbusy(mem_rbusy), .mem_wbusy(mem_wbusy), .reset(reset));

    initial clk = 0;
    always #5 clk = ~clk;

    task clear_mem; begin for(i=0;i<4096;i=i+1) mem[i]=32'h00000013; end endtask
    task do_reset; begin reset=0; @(posedge clk); @(posedge clk); reset=1; end endtask
    task halt_at; input [31:0] t; input integer lim; integer c;
        begin for(c=0;c<lim;c=c+1) begin @(posedge clk); if(mem_addr==t&&mem_rstrb) c=lim; end end endtask
    task check; input [31:0] a; input [31:0] e; input [255:0] l;
        begin total_cnt=total_cnt+1;
        if(mem[a[31:2]]===e) begin $display("  [PASS] %0s — 0x%08h",l,mem[a[31:2]]); pass_cnt=pass_cnt+1; end
        else begin $display("  [FAIL] %0s — exp 0x%08h got 0x%08h",l,e,mem[a[31:2]]); fail_cnt=fail_cnt+1; end
    end endtask

    // Test: Shift by zero
    task test_shift_zero; begin
        $display("\n--- Shift by zero (no change) ---");
        clear_mem();
        mem[0]=32'h0AB00093;  // addi x1,x0,0xAB (=171)
        mem[1]=32'h00009113;  // slli x2,x1,0   => 171
        mem[2]=32'h0000D193;  // srli x3,x1,0   => 171
        mem[3]=32'h00202023;  // sw x2,0(x0)
        mem[4]=32'h00302223;  // sw x3,4(x0)
        mem[5]=32'h0000006F;
        do_reset(); halt_at(32'd20,300);
        check(32'h0,32'h000000AB,"SLLI by 0");
        check(32'h4,32'h000000AB,"SRLI by 0");
    end endtask

    // Test: SLL maximum shift (31 bits)
    task test_sll_max; begin
        $display("\n--- SLL by 31 ---");
        clear_mem();
        mem[0]=32'h00100093;  // addi x1,x0,1
        mem[1]=32'h01F09113;  // slli x2,x1,31  => 0x80000000
        mem[2]=32'h00202023;  // sw x2,0(x0)
        mem[3]=32'h0000006F;
        do_reset(); halt_at(32'd12,300);
        check(32'h0,32'h80000000,"SLL 1<<31 = 0x80000000");
    end endtask

    // Test: SRA on negative number
    task test_sra_negative; begin
        $display("\n--- SRA on negative number ---");
        clear_mem();
        mem[0]=32'h80000093;  // addi x1,x0,-2048 + nah, use LUI
        // lui x1, 0xFFFFF => 0xFFFFF000, then addi -256 => 0xFFFFF000 + 0xFFFFFF00? that's complex
        // Simply: addi x1, x0, -16 => 0xFFFFFFF0
        mem[0]=32'hFF000093;  // addi x1,x0,-256 => 0xFFFFFF00 (nope, -256 = 0xF00 as 12 bit...)
        // addi x1, x0, -16 : imm = 0xFF0 => 32'hFF008093? No.
        // -16 in 12-bit: 0xFF0. Encoding: imm=111111110000, rs1=00000, funct3=000, rd=00001
        // 111111110000_00000_000_00001_0010011 = FF000093
        // Wait that's -256. -16 = 0xFFFF FFF0. As 12-bit: 0xFF0 = -16.
        // 1111 1111 0000 => FF0 => imm[11:0]=0xFF0
        // [31:20]=111111110000, [19:15]=00000, [14:12]=000, [11:7]=00001, [6:0]=0010011
        // = 0xFF000093 — but that's -256 not -16!
        // -16 = 0xFF0 as 12 bits? No: 0xFF0 = -16 in decimal is wrong.
        // -16 signed 12-bit = 1111 1111 0000 = 0xFF0 = wait, 0xFF0 = 4080? No, signed: -16.
        // Actually 0xFF0 in 12-bit signed: bit 11=1, so negative. value = -(4096-4080) = -16. Yes!
        // Encoding: FF008093
        mem[0]=32'hFF008093;  // addi x1, x0, -16  => 0xFFFFFFF0
        // Actually let me double check: the instruction addi x1, x0, imm where imm = -16
        // imm[11:0] = 0xFF0 (since -16 = 0xFFFFFFF0, and the 12-bit field is 0xFF0)
        // Full encoding: 1111_1111_0000_00000_000_00001_0010011
        //              = FF0_00_0_00001_0010011
        // Let me just compute: 0xFF0 << 20 = 0xFF000000, OR'd with 0x00000093
        // = 0xFF000093 — that's -256 actually! Because 0xFF0 in the 12-bit field...
        // Wait: 0xFF0 as a 12-bit signed value:
        //   binary: 1111 1111 0000
        //   sign bit = 1, so negative
        //   magnitude = ~(111111110000) + 1 = 000000001111 + 1 = 000000010000 = 16
        //   So -16. OK so 0xFF000093 IS addi x1, x0, -16.
        // Hmm but in 32 bits the immediate field is inst[31:20].
        // For 0xFF000093: inst[31:20] = 0xFF0 = 1111_1111_0000. Sign-extend: 0xFFFF_FFF0 = -16. Correct!

        mem[0]=32'hFF000093;  // addi x1, x0, -16  => 0xFFFFFFF0
        // (Actually earlier I said this is -256. Let me recheck:
        //  0xFF0 in 12-bit signed is: sign=1. Two's complement of 111111110000:
        //  invert = 000000001111, +1 = 000000010000 = 16. So this IS -16.)
        // BUT WAIT: original comment on line said -256. Let me verify differently.
        // 0xFF000093 => bits[31:20] = 1111_1111_0000 = 0xFF0.
        // Sign extended to 32 bits: 0xFFFF_FFF0. 
        // 0xFFFF_FFF0 as signed = -16. YES, it IS -16. My -256 comment was wrong above.

        mem[1]=32'h4020D113;  // srai x2,x1,2  => -16 >>> 2 = -4 = 0xFFFFFFFC
        mem[2]=32'h00202023;  // sw x2,0(x0)
        mem[3]=32'h0000006F;
        do_reset(); halt_at(32'd12,300);
        check(32'h0,32'hFFFFFFFC,"SRA -16>>>2 = -4");
    end endtask

    // Test: SRL on negative (should NOT sign-extend)
    task test_srl_negative; begin
        $display("\n--- SRL on negative (no sign ext) ---");
        clear_mem();
        mem[0]=32'hFF000093;  // addi x1, x0, -16  => 0xFFFFFFF0
        mem[1]=32'h0020D113;  // srli x2,x1,2   => 0x3FFFFFFC
        mem[2]=32'h00202023;
        mem[3]=32'h0000006F;
        do_reset(); halt_at(32'd12,300);
        check(32'h0,32'h3FFFFFFC,"SRL -16>>2 = 0x3FFFFFFC (logical)");
    end endtask

    // Test: ANDI/ORI/XORI
    task test_imm_logic; begin
        $display("\n--- ANDI / ORI / XORI ---");
        clear_mem();
        mem[0]=32'h0FF00093;  // addi x1, x0, 0xFF
        mem[1]=32'h0F00F113;  // andi x2, x1, 0xF0  (0xFF & 0xF0 = 0xF0)
        // andi: imm=0x0F0, rs1=x1, funct3=111, rd=x2
        // wait funct3 for ANDI = 111
        // [31:20]=000011110000, [19:15]=00001, [14:12]=111, [11:7]=00010, [6:0]=0010011
        // = 0F00F113 — correct
        mem[2]=32'h0550E193;  // ori  x3, x1, 0x55  (0xFF | 0x55 = 0xFF)
        // ori: imm=0x055, rs1=x1, funct3=110, rd=x3
        // = 0550E193
        mem[3]=32'h0FF0C213;  // xori x4, x1, 0xFF  (0xFF ^ 0xFF = 0)
        // xori: imm=0x0FF, rs1=x1, funct3=100, rd=x4
        // [31:20]=000011111111, [19:15]=00001, [14:12]=100, [11:7]=00100, [6:0]=0010011
        // = 0FF0C213
        mem[4]=32'h00202023;  // sw x2,0(x0)
        mem[5]=32'h00302223;  // sw x3,4(x0)
        mem[6]=32'h00402423;  // sw x4,8(x0)
        mem[7]=32'h0000006F;
        do_reset(); halt_at(32'd28,400);
        check(32'h0,32'h000000F0,"ANDI 0xFF&0xF0=0xF0");
        check(32'h4,32'h000000FF,"ORI 0xFF|0x55=0xFF");
        check(32'h8,32'h00000000,"XORI 0xFF^0xFF=0");
    end endtask

    // Test: Register-register AND/OR/XOR
    task test_reg_logic; begin
        $display("\n--- AND / OR / XOR (reg-reg) ---");
        clear_mem();
        mem[0]=32'h0AA00093;  // addi x1, x0, 0xAA (170)
        mem[1]=32'h05500113;  // addi x2, x0, 0x55 (85)
        mem[2]=32'h0020F1B3;  // and x3,x1,x2  (0xAA & 0x55 = 0x00)
        mem[3]=32'h0020E233;  // or  x4,x1,x2  (0xAA | 0x55 = 0xFF)
        mem[4]=32'h0020C2B3;  // xor x5,x1,x2  (0xAA ^ 0x55 = 0xFF)
        mem[5]=32'h00302023;  // sw x3,0(x0)
        mem[6]=32'h00402223;  // sw x4,4(x0)
        mem[7]=32'h00502423;  // sw x5,8(x0)
        mem[8]=32'h0000006F;
        do_reset(); halt_at(32'd32,400);
        check(32'h0,32'h00000000,"AND 0xAA&0x55=0x00");
        check(32'h4,32'h000000FF,"OR 0xAA|0x55=0xFF");
        check(32'h8,32'h000000FF,"XOR 0xAA^0x55=0xFF");
    end endtask

    initial begin
        $display("============================================================");
        $display("  TB4: Shift & Bitwise Logic");
        $display("============================================================");
        pass_cnt=0; fail_cnt=0; total_cnt=0; mem_rbusy=0; mem_wbusy=0;
        test_shift_zero(); test_sll_max(); test_sra_negative();
        test_srl_negative(); test_imm_logic(); test_reg_logic();
        $display("\n============================================================");
        $display("  TB4 RESULTS: %0d / %0d passed",pass_cnt,total_cnt);
        if(fail_cnt==0) $display("  >>> ALL TESTS PASSED <<<");
        else $display("  >>> %0d TESTS FAILED <<<",fail_cnt);
        $display("============================================================\n");
        $finish;
    end
    initial begin #800000; $display("[TIMEOUT]"); $finish; end
endmodule
