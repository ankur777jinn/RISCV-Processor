// =============================================================================
// Testbench 1: ALU Arithmetic Corner Cases
// Tests ADD, SUB, ADDI with overflow, underflow, boundary values,
// chained operations, and zero-register behavior.
// =============================================================================

`timescale 1ns/1ps

module tb1_alu_arithmetic;

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
    // Clock — 100 MHz
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
                mem[i] = 32'h00000013;  // NOP
        end
    endtask

    task do_reset;
        begin
            reset = 0;
            @(posedge clk); @(posedge clk);
            reset = 1;
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
    // Test 1: Signed overflow (positive + positive → negative)
    // =========================================================================
    task test_overflow;
        begin
            $display("\n--- Test 1a: Signed Overflow ---");
            clear_mem();
            // 0x7FFFFFFF + 1 should wrap to 0x80000000
            mem[0] = 32'h7FFFF0B7;  // lui  x1, 0x7FFFF        => 0x7FFFF000
            mem[1] = 32'hFFF08093;  // addi x1, x1, 0xFFF(=-1)  => 0x7FFFFEFF? No...
            // Let's do it properly:
            // lui x1, 0x80000 => 0x80000000, then addi x1,x1,-1 => 0x7FFFFFFF
            mem[0] = 32'h800000B7;  // lui  x1, 0x80000     => 0x80000000
            mem[1] = 32'hFFF08093;  // addi x1, x1, -1      => 0x7FFFFFFF
            mem[2] = 32'h00100113;  // addi x2, x0, 1
            mem[3] = 32'h002081B3;  // add  x3, x1, x2      => 0x80000000 (overflow!)
            mem[4] = 32'h00302023;  // sw   x3, 0(x0)
            mem[5] = 32'h0000006F;  // jal  x0, 0 (halt)
            do_reset();
            halt_at(32'd20, 300);
            check(32'h0, 32'h80000000, "Overflow: 0x7FFFFFFF+1=0x80000000");
        end
    endtask

    // =========================================================================
    // Test 2: Signed underflow (negative + negative → positive)
    // =========================================================================
    task test_underflow;
        begin
            $display("\n--- Test 1b: Signed Underflow ---");
            clear_mem();
            // 0x80000000 - 1 = 0x7FFFFFFF
            mem[0] = 32'h800000B7;  // lui  x1, 0x80000     => 0x80000000
            mem[1] = 32'h00100113;  // addi x2, x0,  1
            mem[2] = 32'h402081B3;  // sub  x3, x1, x2      => 0x7FFFFFFF
            mem[3] = 32'h00302023;  // sw   x3, 0(x0)
            mem[4] = 32'h0000006F;  // jal  x0, 0 (halt)
            do_reset();
            halt_at(32'd16, 300);
            check(32'h0, 32'h7FFFFFFF, "Underflow: 0x80000000 - 1 = 0x7FFFFFFF");
        end
    endtask

    // =========================================================================
    // Test 3: ADD with zero
    // =========================================================================
    task test_add_zero;
        begin
            $display("\n--- Test 1c: ADD with zero ---");
            clear_mem();
            mem[0] = 32'h0FF00093;  // addi x1, x0, 255
            mem[1] = 32'h000080B3;  // add  x1, x1, x0      => 255 (unchanged)
            mem[2] = 32'h00102023;  // sw   x1, 0(x0)
            mem[3] = 32'h0000006F;  // jal  x0, 0 (halt)
            do_reset();
            halt_at(32'd12, 300);
            check(32'h0, 32'h000000FF, "ADD x1 + x0 = 255 (unchanged)");
        end
    endtask

    // =========================================================================
    // Test 4: SUB producing zero
    // =========================================================================
    task test_sub_to_zero;
        begin
            $display("\n--- Test 1d: SUB producing zero ---");
            clear_mem();
            mem[0] = 32'h05A00093;  // addi x1, x0, 90
            mem[1] = 32'h05A00113;  // addi x2, x0, 90
            mem[2] = 32'h402081B3;  // sub  x3, x1, x2      => 0
            mem[3] = 32'h00302023;  // sw   x3, 0(x0)
            mem[4] = 32'h0000006F;  // jal  x0, 0 (halt)
            do_reset();
            halt_at(32'd16, 300);
            check(32'h0, 32'h00000000, "SUB 90-90 = 0");
        end
    endtask

    // =========================================================================
    // Test 5: Chained ADDI (accumulate through multiple adds)
    // =========================================================================
    task test_chained_addi;
        begin
            $display("\n--- Test 1e: Chained ADDI ---");
            clear_mem();
            mem[0] = 32'h00A00093;  // addi x1, x0,  10
            mem[1] = 32'h01408093;  // addi x1, x1,  20     => 30
            mem[2] = 32'h01E08093;  // addi x1, x1,  30     => 60
            mem[3] = 32'h02808093;  // addi x1, x1,  40     => 100
            mem[4] = 32'h03208093;  // addi x1, x1,  50     => 150
            mem[5] = 32'h00102023;  // sw   x1, 0(x0)
            mem[6] = 32'h0000006F;  // jal  x0, 0 (halt)
            do_reset();
            halt_at(32'd24, 400);
            check(32'h0, 32'h00000096, "Chained ADDI 10+20+30+40+50 = 150");
        end
    endtask

    // =========================================================================
    // Test 6: Write to x0 should be ignored
    // =========================================================================
    task test_x0_hardwired;
        begin
            $display("\n--- Test 1f: x0 hardwired to zero ---");
            clear_mem();
            mem[0] = 32'h0FF00013;  // addi x0, x0, 255  (attempt to write x0)
            mem[1] = 32'h00000033;  // add  x0, x0, x0   (attempt to write x0)
            // x0 should still be 0. Use it as a base to store.
            mem[2] = 32'h00002023;  // sw   x0, 0(x0)    => stores 0
            mem[3] = 32'h0000006F;  // jal  x0, 0 (halt)
            do_reset();
            halt_at(32'd12, 300);
            check(32'h0, 32'h00000000, "x0 remains zero after write attempts");
        end
    endtask

    // =========================================================================
    // Test 7: Large negative ADDI
    // =========================================================================
    task test_negative_addi;
        begin
            $display("\n--- Test 1g: Large negative ADDI ---");
            clear_mem();
            mem[0] = 32'h00A00093;  // addi x1, x0, 10
            mem[1] = 32'h80008093;  // addi x1, x1, -2048   => 10 - 2048 = -2038 = 0xFFFFF80A
            mem[2] = 32'h00102023;  // sw   x1, 0(x0)
            mem[3] = 32'h0000006F;  // jal  x0, 0 (halt)
            do_reset();
            halt_at(32'd12, 300);
            check(32'h0, 32'hFFFFF80A, "ADDI 10 + (-2048) = -2038");
        end
    endtask

    // =========================================================================
    // Test 8: Self–subtraction (subtract a register from itself)
    // =========================================================================
    task test_self_sub;
        begin
            $display("\n--- Test 1h: Self-subtraction ---");
            clear_mem();
            mem[0] = 32'hABCDE0B7;  // lui  x1, 0xABCDE      => 0xABCDE000
            mem[1] = 32'h401080B3;  // sub  x1, x1, x1        => 0
            mem[2] = 32'h00102023;  // sw   x1, 0(x0)
            mem[3] = 32'h0000006F;  // jal  x0, 0 (halt)
            do_reset();
            halt_at(32'd12, 300);
            check(32'h0, 32'h00000000, "Self-sub: x1 - x1 = 0");
        end
    endtask

    // =========================================================================
    // Main
    // =========================================================================
    initial begin
        $display("============================================================");
        $display("  TB1: ALU Arithmetic Corner Cases");
        $display("============================================================");
        pass_cnt = 0; fail_cnt = 0; total_cnt = 0;
        mem_rbusy = 0; mem_wbusy = 0;

        test_overflow();
        test_underflow();
        test_add_zero();
        test_sub_to_zero();
        test_chained_addi();
        test_x0_hardwired();
        test_negative_addi();
        test_self_sub();

        $display("\n============================================================");
        $display("  TB1 RESULTS:  %0d / %0d passed", pass_cnt, total_cnt);
        if (fail_cnt == 0) $display("  >>> ALL TESTS PASSED <<<");
        else               $display("  >>> %0d TESTS FAILED <<<", fail_cnt);
        $display("============================================================\n");
        $finish;
    end

    initial begin #500000; $display("[TIMEOUT]"); $finish; end

endmodule
