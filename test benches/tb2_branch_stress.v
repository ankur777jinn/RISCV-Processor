// =============================================================================
// Testbench 2: Branch Instruction Stress Test
// Exhaustive test of BEQ, BNE, BLT, BGE, BLTU, BGEU with edge cases:
//   - equal values, negative comparison, unsigned boundary, backward branch
// =============================================================================

`timescale 1ns/1ps

module tb2_branch_stress;

    reg         clk;
    reg         reset;
    wire [31:0] mem_addr, mem_wdata;
    wire [3:0]  mem_wmask;
    wire [31:0] mem_rdata;
    wire        mem_rstrb;
    reg         mem_rbusy, mem_wbusy;

    reg [31:0] mem [0:4095];
    reg [31:0] rd_reg;

    always @(posedge clk) begin
        if (mem_rstrb) rd_reg <= mem[mem_addr[31:2]];
    end
    assign mem_rdata = rd_reg;

    always @(posedge clk) begin
        if (mem_wmask[0]) mem[mem_addr[31:2]][7:0]   <= mem_wdata[7:0];
        if (mem_wmask[1]) mem[mem_addr[31:2]][15:8]  <= mem_wdata[15:8];
        if (mem_wmask[2]) mem[mem_addr[31:2]][23:16] <= mem_wdata[23:16];
        if (mem_wmask[3]) mem[mem_addr[31:2]][31:24] <= mem_wdata[31:24];
    end

    always @(*) begin mem_rbusy = 0; mem_wbusy = 0; end

    riscv_processor #(.RESET_ADDR(32'h00000000)) dut (
        .clk(clk), .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_wmask(mem_wmask), .mem_rdata(mem_rdata), .mem_rstrb(mem_rstrb),
        .mem_rbusy(mem_rbusy), .mem_wbusy(mem_wbusy), .reset(reset)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer pass_cnt, fail_cnt, total_cnt, i;

    task clear_mem; begin for (i=0;i<4096;i=i+1) mem[i]=32'h00000013; end endtask
    task do_reset;  begin reset=0; @(posedge clk); @(posedge clk); reset=1; end endtask
    task halt_at;
        input [31:0] target; input integer limit; integer c;
        begin for(c=0;c<limit;c=c+1) begin @(posedge clk);
            if(mem_addr==target && mem_rstrb) c=limit; end end
    endtask
    task check;
        input [31:0] addr; input [31:0] expected; input [255:0] label;
        begin total_cnt=total_cnt+1;
            if(mem[addr[31:2]]===expected) begin
                $display("  [PASS] %0s — got 0x%08h",label,mem[addr[31:2]]);
                pass_cnt=pass_cnt+1;
            end else begin
                $display("  [FAIL] %0s — expected 0x%08h, got 0x%08h",label,expected,mem[addr[31:2]]);
                fail_cnt=fail_cnt+1;
            end
        end
    endtask

    // =========================================================================
    // Test 1: BEQ — taken and not-taken
    // =========================================================================
    task test_beq;
        begin
            $display("\n--- BEQ: taken & not-taken ---");
            clear_mem();
            mem[0]  = 32'h00500093;  // addi x1, x0, 5
            mem[1]  = 32'h00500113;  // addi x2, x0, 5
            mem[2]  = 32'h00300193;  // addi x3, x0, 3  (different)
            // BEQ x1,x2 → should be taken (+8)
            mem[3]  = 32'h00208463;  // beq x1, x2, +8 → addr 20
            mem[4]  = 32'h06300213;  // addi x4, x0, 99 (skipped)
            // addr 20
            mem[5]  = 32'h01500213;  // addi x4, x0, 21 (landed)
            // BEQ x1,x3 → should NOT be taken
            mem[6]  = 32'h00308463;  // beq x1, x3, +8
            mem[7]  = 32'h02D00293;  // addi x5, x0, 45 (executed, NOT skipped)
            // addr 32
            mem[8]  = 32'h00000013;  // nop
            mem[9]  = 32'h00402023;  // sw x4, 0(x0)
            mem[10] = 32'h00502223;  // sw x5, 4(x0)
            mem[11] = 32'h0000006F;  // halt
            do_reset();
            halt_at(32'd44, 400);
            check(32'h0, 32'h00000015, "BEQ taken → x4=21");
            check(32'h4, 32'h0000002D, "BEQ not-taken → x5=45");
        end
    endtask

    // =========================================================================
    // Test 2: BNE — taken and not-taken
    // =========================================================================
    task test_bne;
        begin
            $display("\n--- BNE: taken & not-taken ---");
            clear_mem();
            mem[0]  = 32'h00A00093;  // addi x1, x0, 10
            mem[1]  = 32'h00700113;  // addi x2, x0, 7
            mem[2]  = 32'h00A00193;  // addi x3, x0, 10
            // BNE x1,x2 → taken (10!=7)
            mem[3]  = 32'h00209463;  // bne x1, x2, +8
            mem[4]  = 32'h06300213;  // addi x4,x0,99 (skipped)
            mem[5]  = 32'h00100213;  // addi x4,x0,1  (landed)
            // BNE x1,x3 → NOT taken (10==10)
            mem[6]  = 32'h00309463;  // bne x1, x3, +8
            mem[7]  = 32'h00200293;  // addi x5,x0,2  (executed)
            mem[8]  = 32'h00000013;  // nop
            mem[9]  = 32'h00402023;  // sw x4, 0(x0)
            mem[10] = 32'h00502223;  // sw x5, 4(x0)
            mem[11] = 32'h0000006F;  // halt
            do_reset();
            halt_at(32'd44, 400);
            check(32'h0, 32'h00000001, "BNE taken → x4=1");
            check(32'h4, 32'h00000002, "BNE not-taken → x5=2");
        end
    endtask

    // =========================================================================
    // Test 3: BLT / BGE with negative numbers
    // =========================================================================
    task test_blt_bge_negative;
        begin
            $display("\n--- BLT / BGE with negatives ---");
            clear_mem();
            mem[0]  = 32'hFFB00093;  // addi x1, x0, -5
            mem[1]  = 32'h00300113;  // addi x2, x0,  3
            // BLT x1,x2 → taken (-5 < 3)
            mem[2]  = 32'h00204463;  // blt x1, x2, +8
            mem[3]  = 32'h06300193;  // skipped
            mem[4]  = 32'h00A00193;  // addi x3,x0,10 (landed)
            // BGE x2,x1 → taken (3 >= -5)
            mem[5]  = 32'h0010D463;  // bge x2, x1, +8  (NOTE: bge rs1=x2,rs2=x1)
            // Encoding: imm[12|10:5]=0000000, rs2=x1=00001, rs1=x2=00010, funct3=101, imm[4:1|11]=0100, op=1100011
            // Actually let me re-encode properly: bge x2, x1, +8
            // imm=8: imm[12]=0, imm[11]=0, imm[10:5]=000000, imm[4:1]=0100, => 
            // [31:25]=0000000, [24:20]=00001(rs2=x1), [19:15]=00010(rs1=x2), [14:12]=101, [11:7]=01000, [6:0]=1100011
            // = 0000000_00001_00010_101_01000_1100011 = 00115463
            mem[5]  = 32'h00115463;  // bge x2, x1, +8
            mem[6]  = 32'h06300213;  // skipped
            mem[7]  = 32'h01400213;  // addi x4,x0,20 (landed)
            // BGE x1,x2 → NOT taken (-5 >= 3 is false)
            mem[8]  = 32'h0020D463;  // bge x1, x2, +8
            mem[9]  = 32'h01E00293;  // addi x5,x0,30 (executed)
            mem[10] = 32'h00000013;  // nop
            mem[11] = 32'h00302023;  // sw x3, 0(x0)
            mem[12] = 32'h00402223;  // sw x4, 4(x0)
            mem[13] = 32'h00502423;  // sw x5, 8(x0)
            mem[14] = 32'h0000006F;  // halt
            do_reset();
            halt_at(32'd56, 500);
            check(32'h0, 32'h0000000A, "BLT -5<3 taken → x3=10");
            check(32'h4, 32'h00000014, "BGE 3>=-5 taken → x4=20");
            check(32'h8, 32'h0000001E, "BGE -5>=3 not taken → x5=30");
        end
    endtask

    // =========================================================================
    // Test 4: BLTU / BGEU unsigned boundary
    // =========================================================================
    task test_bltu_bgeu;
        begin
            $display("\n--- BLTU / BGEU unsigned boundary ---");
            clear_mem();
            mem[0]  = 32'hFFF00093;  // addi x1, x0, -1  (= 0xFFFFFFFF, max unsigned)
            mem[1]  = 32'h00000113;  // addi x2, x0, 0
            // BLTU x2,x1 → taken (0 < 0xFFFFFFFF unsigned)
            mem[2]  = 32'h00116463;  // bltu x2, x1, +8
            mem[3]  = 32'h06300193;  // skipped
            mem[4]  = 32'h00100193;  // addi x3,x0,1 (landed)
            // BLTU x1,x2 → NOT taken (0xFFFFFFFF < 0 is false)
            mem[5]  = 32'h0020E463;  // bltu x1, x2, +8
            mem[6]  = 32'h00200213;  // addi x4,x0,2 (executed)
            // addr 28
            mem[7]  = 32'h00000013;  // nop
            // BGEU x1,x1 → taken (equal)
            mem[8]  = 32'h0010F463;  // bgeu x1, x1, +8
            mem[9]  = 32'h06300293;  // skipped
            mem[10] = 32'h00300293;  // addi x5,x0,3 (landed)
            mem[11] = 32'h00302023;  // sw x3, 0(x0)
            mem[12] = 32'h00402223;  // sw x4, 4(x0)
            mem[13] = 32'h00502423;  // sw x5, 8(x0)
            mem[14] = 32'h0000006F;  // halt
            do_reset();
            halt_at(32'd56, 500);
            check(32'h0, 32'h00000001, "BLTU 0<max taken → x3=1");
            check(32'h4, 32'h00000002, "BLTU max<0 not taken → x4=2");
            check(32'h8, 32'h00000003, "BGEU equal taken → x5=3");
        end
    endtask

    // =========================================================================
    // Test 5: Backward branch (count-down loop)
    // =========================================================================
    task test_backward_branch;
        begin
            $display("\n--- Backward branch (countdown) ---");
            clear_mem();
            // Count from 5 down to 0 and store the final counter
            mem[0] = 32'h00500093;  // addi x1, x0, 5   (counter = 5)
            mem[1] = 32'h00000113;  // addi x2, x0, 0   (zero for compare)
            // addr 8 (loop start):
            mem[2] = 32'hFFF08093;  // addi x1, x1, -1  (counter--)
            mem[3] = 32'hFE209CE3;  // bne  x1, x2, -8  (back to addr 8 if x1 != 0)
            // exit loop: x1 = 0
            mem[4] = 32'h00102023;  // sw x1, 0(x0)
            mem[5] = 32'h0000006F;  // halt
            do_reset();
            halt_at(32'd20, 600);
            check(32'h0, 32'h00000000, "Countdown loop: x1 reaches 0");
        end
    endtask

    // =========================================================================
    // Test 6: BEQ with zero register
    // =========================================================================
    task test_beq_zero;
        begin
            $display("\n--- BEQ x0, x0 (always taken) ---");
            clear_mem();
            mem[0] = 32'h00A00093;  // addi x1, x0, 10
            // BEQ x0,x0 → always taken
            mem[1] = 32'h00000463;  // beq x0, x0, +8 (to addr 12)
            mem[2] = 32'h06300093;  // addi x1,x0,99 (skipped)
            // addr 12:
            mem[3] = 32'h00102023;  // sw x1, 0(x0)
            mem[4] = 32'h0000006F;  // halt
            do_reset();
            halt_at(32'd16, 300);
            check(32'h0, 32'h0000000A, "BEQ x0,x0 always taken → x1=10");
        end
    endtask

    // =========================================================================
    // Main
    // =========================================================================
    initial begin
        $display("============================================================");
        $display("  TB2: Branch Instruction Stress Test");
        $display("============================================================");
        pass_cnt = 0; fail_cnt = 0; total_cnt = 0;
        mem_rbusy = 0; mem_wbusy = 0;

        test_beq();
        test_bne();
        test_blt_bge_negative();
        test_bltu_bgeu();
        test_backward_branch();
        test_beq_zero();

        $display("\n============================================================");
        $display("  TB2 RESULTS:  %0d / %0d passed", pass_cnt, total_cnt);
        if (fail_cnt == 0) $display("  >>> ALL TESTS PASSED <<<");
        else               $display("  >>> %0d TESTS FAILED <<<", fail_cnt);
        $display("============================================================\n");
        $finish;
    end

    initial begin #800000; $display("[TIMEOUT]"); $finish; end

endmodule
