// =============================================================================
// Testbench 3: Load/Store Width Variants
// Tests LB, LBU, LH, LHU, LW, SB, SH, SW with sign/zero extension
// =============================================================================

`timescale 1ns/1ps

module tb3_load_store_variants;

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

    // Test 1: SW then LW roundtrip
    task test_sw_lw; begin
        $display("\n--- SW/LW roundtrip ---");
        clear_mem(); mem[256]=0;
        mem[0]=32'h40000093; mem[1]=32'hABC00113; mem[2]=32'h0020A023;
        mem[3]=32'h0000A183; mem[4]=32'h00302023; mem[5]=32'h0000006F;
        do_reset(); halt_at(32'd20,400);
        check(32'h0,32'hFFFFFABC,"SW/LW roundtrip");
    end endtask

    // Test 2: LB sign extension (0x80 -> 0xFFFFFF80)
    task test_lb_sign; begin
        $display("\n--- LB sign extension ---");
        clear_mem(); mem[256]=32'h00000080;
        mem[0]=32'h40000093; mem[1]=32'h00008103; mem[2]=32'h00202023; mem[3]=32'h0000006F;
        do_reset(); halt_at(32'd12,400);
        check(32'h0,32'hFFFFFF80,"LB sign-ext 0x80");
    end endtask

    // Test 3: LBU zero extension (0x80 -> 0x00000080)
    task test_lbu_zero; begin
        $display("\n--- LBU zero extension ---");
        clear_mem(); mem[256]=32'h00000080;
        mem[0]=32'h40000093; mem[1]=32'h0000C103; mem[2]=32'h00202023; mem[3]=32'h0000006F;
        do_reset(); halt_at(32'd12,400);
        check(32'h0,32'h00000080,"LBU zero-ext 0x80");
    end endtask

    // Test 4: LH sign extension (0x8000 -> 0xFFFF8000)
    task test_lh_sign; begin
        $display("\n--- LH sign extension ---");
        clear_mem(); mem[256]=32'h00008000;
        mem[0]=32'h40000093; mem[1]=32'h00009103; mem[2]=32'h00202023; mem[3]=32'h0000006F;
        do_reset(); halt_at(32'd12,400);
        check(32'h0,32'hFFFF8000,"LH sign-ext 0x8000");
    end endtask

    // Test 5: LHU zero extension
    task test_lhu_zero; begin
        $display("\n--- LHU zero extension ---");
        clear_mem(); mem[256]=32'h00008000;
        mem[0]=32'h40000093; mem[1]=32'h0000D103; mem[2]=32'h00202023; mem[3]=32'h0000006F;
        do_reset(); halt_at(32'd12,400);
        check(32'h0,32'h00008000,"LHU zero-ext 0x8000");
    end endtask

    // Test 6: SB + SH composite
    task test_sb_sh; begin
        $display("\n--- SB/SH composite ---");
        clear_mem(); mem[256]=32'h00000000;
        mem[0]=32'h40000093; mem[1]=32'h0AB00113;
        mem[2]=32'h00208023; // sb x2,0(x1)
        mem[3]=32'h12300113; // addi x2,x0,0x123
        mem[4]=32'h00209123; // sh x2,2(x1)
        mem[5]=32'h0000A183; // lw x3,0(x1)
        mem[6]=32'h00302023; mem[7]=32'h0000006F;
        do_reset(); halt_at(32'd28,500);
        check(32'h0,32'h012300AB,"SB byte0 + SH halfword1 composite");
    end endtask

    // Test 7: Load into x0 discards
    task test_load_x0; begin
        $display("\n--- Load into x0 discards ---");
        clear_mem(); mem[256]=32'hDEADBEEF;
        mem[0]=32'h40000093; mem[1]=32'h0000A003; mem[2]=32'h00002023; mem[3]=32'h0000006F;
        do_reset(); halt_at(32'd12,400);
        check(32'h0,32'h00000000,"Load into x0 discarded");
    end endtask

    initial begin
        $display("============================================================");
        $display("  TB3: Load/Store Width Variants");
        $display("============================================================");
        pass_cnt=0; fail_cnt=0; total_cnt=0; mem_rbusy=0; mem_wbusy=0;
        test_sw_lw(); test_lb_sign(); test_lbu_zero();
        test_lh_sign(); test_lhu_zero(); test_sb_sh(); test_load_x0();
        $display("\n============================================================");
        $display("  TB3 RESULTS: %0d / %0d passed",pass_cnt,total_cnt);
        if(fail_cnt==0) $display("  >>> ALL TESTS PASSED <<<");
        else $display("  >>> %0d TESTS FAILED <<<",fail_cnt);
        $display("============================================================\n");
        $finish;
    end
    initial begin #800000; $display("[TIMEOUT]"); $finish; end
endmodule
