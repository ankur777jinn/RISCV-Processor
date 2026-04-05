// =============================================================================
// Testbench 5: JAL / JALR and Link Register
// Tests jump targets, return address saving, JALR with offset, function call
// =============================================================================

`timescale 1ns/1ps

module tb5_jump_link;

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

    // Test 1: JAL saves return address
    task test_jal_link; begin
        $display("\n--- JAL saves return address ---");
        clear_mem();
        // addr 0: jal x1, 12 => x1 = 4, jump to addr 12
        mem[0]=32'h00C000EF;  // jal x1, 12
        mem[1]=32'h00000013;  // nop (skipped)
        mem[2]=32'h00000013;  // nop (skipped)
        // addr 12: store x1 (should be 4 = return addr)
        mem[3]=32'h00102023;  // sw x1, 0(x0)
        mem[4]=32'h0000006F;
        do_reset(); halt_at(32'd16,300);
        check(32'h0,32'h00000004,"JAL return addr = 4");
    end endtask

    // Test 2: JALR jump to register + offset
    task test_jalr_offset; begin
        $display("\n--- JALR with offset ---");
        clear_mem();
        mem[0]=32'h01000093;  // addi x1, x0, 16   (base)
        // jalr x2, 8(x1) => target = (16+8)&~1 = 24, x2 = 8 (PC+4)
        // jalr rd=x2, rs1=x1, imm=8
        // imm=000000001000, rs1=00001, funct3=000, rd=00010, op=1100111
        // = 00808167
        mem[1]=32'h00808167;  // jalr x2, 8(x1) => jump to 24, x2=8
        mem[2]=32'h00000013;  // skipped
        mem[3]=32'h00000013;  // skipped
        mem[4]=32'h00000013;  // skipped
        mem[5]=32'h00000013;  // skipped
        // addr 24
        mem[6]=32'h00202023;  // sw x2, 0(x0) => should store 8
        mem[7]=32'h0000006F;
        do_reset(); halt_at(32'd28,300);
        check(32'h0,32'h00000008,"JALR return addr = 8");
    end endtask

    // Test 3: JAL to x0 (unconditional jump, no link)
    task test_jal_x0; begin
        $display("\n--- JAL to x0 (no link) ---");
        clear_mem();
        mem[0]=32'h00500093;  // addi x1, x0, 5
        mem[1]=32'h00C0006F;  // jal x0, 12 => jump to addr 16, x0 stays 0
        mem[2]=32'h06300093;  // addi x1,x0,99 (skipped)
        mem[3]=32'h06300093;  // addi x1,x0,99 (skipped)
        // addr 16
        mem[4]=32'h00102023;  // sw x1, 0(x0)  => 5 (unchanged)
        mem[5]=32'h00002223;  // sw x0, 4(x0)  => 0 (x0 not modified)
        mem[6]=32'h0000006F;
        do_reset(); halt_at(32'd24,300);
        check(32'h0,32'h00000005,"JAL x0: x1 not clobbered (5)");
        check(32'h4,32'h00000000,"JAL x0: x0 still 0");
    end endtask

    // Test 4: Function call and return pattern
    task test_call_return; begin
        $display("\n--- Call/return pattern ---");
        clear_mem();
        // main: call function at addr 24, then store result
        mem[0]=32'h00A00093;  // addi x1, x0, 10  (argument)
        mem[1]=32'h010000EF;  // jal ra(x1), 16   => x1=8, jump to addr 24
        // Oops that clobbers x1. Use x1=ra convention. Let me redesign:
        // Use x10 as argument, x1 as return address (ra)
        mem[0]=32'h00A00513;  // addi x10, x0, 10  (argument in x10)
        mem[1]=32'h010000EF;  // jal x1, 16        => x1=8, jump to addr 24
        // return here: addr 8
        mem[2]=32'h00A02023;  // sw x10, 0(x0)     => store result
        mem[3]=32'h0000006F;  // halt at addr 12
        // padding
        mem[4]=32'h00000013;
        mem[5]=32'h00000013;
        // function at addr 24: double x10 and return
        mem[6]=32'h00A50533;  // add x10, x10, x10  (double)
        mem[7]=32'h00008067;  // jalr x0, 0(x1)     (return: jump to x1, don't save link)
        do_reset(); halt_at(32'd12,400);
        check(32'h0,32'h00000014,"Call/return: 10*2=20");
    end endtask

    // Test 5: JALR clears LSB
    task test_jalr_lsb; begin
        $display("\n--- JALR clears LSB ---");
        clear_mem();
        // target = 17 (odd), JALR should clear bit 0 => jump to 16
        mem[0]=32'h01100093;  // addi x1, x0, 17
        // jalr x2, 0(x1) => target = (17+0) & ~1 = 16
        mem[1]=32'h00008167;  // jalr x2, 0(x1)
        mem[2]=32'h00000013;  // skipped
        mem[3]=32'h00000013;  // skipped
        // addr 16:
        mem[4]=32'h00202023;  // sw x2, 0(x0) => should be 8 (return addr)
        mem[5]=32'h0000006F;
        do_reset(); halt_at(32'd20,300);
        check(32'h0,32'h00000008,"JALR cleared LSB, return addr=8");
    end endtask

    initial begin
        $display("============================================================");
        $display("  TB5: JAL / JALR and Link Register");
        $display("============================================================");
        pass_cnt=0; fail_cnt=0; total_cnt=0; mem_rbusy=0; mem_wbusy=0;
        test_jal_link(); test_jalr_offset(); test_jal_x0();
        test_call_return(); test_jalr_lsb();
        $display("\n============================================================");
        $display("  TB5 RESULTS: %0d / %0d passed",pass_cnt,total_cnt);
        if(fail_cnt==0) $display("  >>> ALL TESTS PASSED <<<");
        else $display("  >>> %0d TESTS FAILED <<<",fail_cnt);
        $display("============================================================\n");
        $finish;
    end
    initial begin #800000; $display("[TIMEOUT]"); $finish; end
endmodule
