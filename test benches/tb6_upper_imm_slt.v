// =============================================================================
// Testbench 6: LUI / AUIPC / SLT / SLTU / SLTI / SLTIU
// Tests upper immediate instructions and all set-less-than variants
// =============================================================================

`timescale 1ns/1ps

module tb6_upper_imm_slt;

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

    // Test 1: LUI loads upper 20 bits
    task test_lui_basic; begin
        $display("\n--- LUI basic ---");
        clear_mem();
        mem[0]=32'hABCDE0B7;  // lui x1, 0xABCDE   => 0xABCDE000
        mem[1]=32'h00102023;  // sw x1, 0(x0)
        mem[2]=32'h0000006F;
        do_reset(); halt_at(32'd8,300);
        check(32'h0,32'hABCDE000,"LUI 0xABCDE000");
    end endtask

    // Test 2: LUI + ADDI to form 32-bit constant
    task test_lui_addi; begin
        $display("\n--- LUI + ADDI = 32-bit constant ---");
        clear_mem();
        mem[0]=32'hDEADB0B7;  // lui x1, 0xDEADB   => 0xDEADB000
        mem[1]=32'hEEF08093;  // addi x1,x1,0xEEF   => sign ext: 0xEEF = -273? No...
        // 0xEEF = 1110 1110 1111. Bit 11 = 1, so sign-exted = 0xFFFFFEEF.
        // 0xDEADB000 + 0xFFFFFEEF = 0xDEADAEEF. Not ideal.
        // For 0xDEADBEEF: upper = 0xDEADC (since 0xBEEF has bit 11 set, add 1 to upper)
        // then lower = 0xBEEF = -0x411 + 0x1000? Actually 0xBEEF sign-extends to 0xFFFFFEEF
        // LUI 0xDEADC + ADDI 0xEEF: 0xDEADC000 + 0xFFFFFEEF = 0xDEADBEEF. But 0xEEF bit11=1, 
        // so ADDI adds 0xFFFFFEEF. Let's check: 0xDEADC000 + 0xFFFFFEEF = ?
        // = 0xDEADC000 - 0x111 = 0xDEADBEEF. Wait that doesn't add up...
        // 0xFFFFFEEF = -0x111. So 0xDEADC000 - 0x111 = 0xDEADBEEF. Hmm:
        // 0xDEADC000 - 0x0111 = 0xDEADBEEF. Yes!
        // But imm field is 0xEEF which is -0x111 in signed 12-bit. So instruction:
        // addi x1,x1, -0x111: imm = 0xEEF
        mem[0]=32'hDEADC0B7;  // lui x1, 0xDEADC
        mem[1]=32'hEEF08093;  // addi x1, x1, -273 (0xEEF => -0x111)
        mem[2]=32'h00102023;
        mem[3]=32'h0000006F;
        do_reset(); halt_at(32'd12,300);
        check(32'h0,32'hDEADBEEF,"LUI+ADDI = 0xDEADBEEF");
    end endtask

    // Test 3: AUIPC at different PCs
    task test_auipc; begin
        $display("\n--- AUIPC ---");
        clear_mem();
        // addr 0: auipc x1, 0 => x1 = 0 + 0 = 0
        mem[0]=32'h00000097;  // auipc x1, 0    => PC=0, x1=0
        // addr 4: auipc x2, 1 => x2 = 4 + 0x1000 = 0x1004
        mem[1]=32'h00001117;  // auipc x2, 1    => PC=4, x2=0x1004
        // addr 8: auipc x3, 0x10 => x3 = 8 + 0x10000 = 0x10008
        mem[2]=32'h00010197;  // auipc x3, 0x10 => PC=8, x3=0x10008
        mem[3]=32'h00102023;  // sw x1, 0(x0)
        mem[4]=32'h00202223;  // sw x2, 4(x0)
        mem[5]=32'h00302423;  // sw x3, 8(x0)
        mem[6]=32'h0000006F;
        do_reset(); halt_at(32'd24,400);
        check(32'h0,32'h00000000,"AUIPC at PC=0, imm=0");
        check(32'h4,32'h00001004,"AUIPC at PC=4, imm=1");
        check(32'h8,32'h00010008,"AUIPC at PC=8, imm=0x10");
    end endtask

    // Test 4: SLT signed comparison
    task test_slt_signed; begin
        $display("\n--- SLT signed ---");
        clear_mem();
        mem[0]=32'hFFB00093;  // addi x1, x0, -5
        mem[1]=32'h00300113;  // addi x2, x0, 3
        // SLT x3, x1, x2: -5 < 3 => 1
        mem[2]=32'h0020A1B3;  // slt x3, x1, x2
        // SLT x4, x2, x1: 3 < -5 => 0
        mem[3]=32'h00112233;  // slt x4, x2, x1
        mem[4]=32'h00302023;  // sw x3, 0(x0)
        mem[5]=32'h00402223;  // sw x4, 4(x0)
        mem[6]=32'h0000006F;
        do_reset(); halt_at(32'd24,300);
        check(32'h0,32'h00000001,"SLT -5<3 = 1");
        check(32'h4,32'h00000000,"SLT 3<-5 = 0");
    end endtask

    // Test 5: SLTU unsigned comparison (negative = large positive)
    task test_sltu; begin
        $display("\n--- SLTU unsigned ---");
        clear_mem();
        mem[0]=32'hFFF00093;  // addi x1, x0, -1  (0xFFFFFFFF)
        mem[1]=32'h00100113;  // addi x2, x0, 1
        // SLTU x3, x2, x1: 1 < 0xFFFFFFFF => 1
        mem[2]=32'h001131B3;  // sltu x3, x2, x1  (R-type: opcode=0x33, funct3=011)
        // SLTU x4, x1, x2: 0xFFFFFFFF < 1 => 0
        mem[3]=32'h0020B233;  // sltu x4, x1, x2
        mem[4]=32'h00302023;
        mem[5]=32'h00402223;
        mem[6]=32'h0000006F;
        do_reset(); halt_at(32'd24,300);
        check(32'h0,32'h00000001,"SLTU 1 < 0xFFFFFFFF = 1");
        check(32'h4,32'h00000000,"SLTU 0xFFFFFFFF < 1 = 0");
    end endtask

    // Test 6: SLTI and SLTIU
    task test_slti_sltiu; begin
        $display("\n--- SLTI / SLTIU ---");
        clear_mem();
        mem[0]=32'h00500093;  // addi x1, x0, 5
        // SLTI x2, x1, 10: 5 < 10 signed => 1
        mem[1]=32'h00A0A113;  // slti x2, x1, 10
        // SLTI x3, x1, 3: 5 < 3 signed => 0
        mem[2]=32'h0030A193;  // slti x3, x1, 3
        // SLTIU x4, x1, 10: 5 < 10 unsigned => 1
        mem[3]=32'h00A0B213;  // sltiu x4, x1, 10
        // SLTIU x5, x1, 1: 5 < 1 unsigned => 0
        mem[4]=32'h0010B293;  // sltiu x5, x1, 1
        mem[5]=32'h00202023;  // sw x2, 0(x0)
        mem[6]=32'h00302223;  // sw x3, 4(x0)
        mem[7]=32'h00402423;  // sw x4, 8(x0)
        mem[8]=32'h00502623;  // sw x5, 12(x0)
        mem[9]=32'h0000006F;
        do_reset(); halt_at(32'd36,400);
        check(32'h0, 32'h00000001,"SLTI 5<10 = 1");
        check(32'h4, 32'h00000000,"SLTI 5<3 = 0");
        check(32'h8, 32'h00000001,"SLTIU 5<10 = 1");
        check(32'hC, 32'h00000000,"SLTIU 5<1 = 0");
    end endtask

    // Test 7: LUI to x0 (should stay zero)
    task test_lui_x0; begin
        $display("\n--- LUI to x0 ---");
        clear_mem();
        mem[0]=32'hABCDE037;  // lui x0, 0xABCDE (should be discarded)
        mem[1]=32'h00002023;  // sw x0, 0(x0) => 0
        mem[2]=32'h0000006F;
        do_reset(); halt_at(32'd8,300);
        check(32'h0,32'h00000000,"LUI x0 stays zero");
    end endtask

    initial begin
        $display("============================================================");
        $display("  TB6: LUI / AUIPC / SLT / SLTU / SLTI / SLTIU");
        $display("============================================================");
        pass_cnt=0; fail_cnt=0; total_cnt=0; mem_rbusy=0; mem_wbusy=0;
        test_lui_basic(); test_lui_addi(); test_auipc();
        test_slt_signed(); test_sltu(); test_slti_sltiu(); test_lui_x0();
        $display("\n============================================================");
        $display("  TB6 RESULTS: %0d / %0d passed",pass_cnt,total_cnt);
        if(fail_cnt==0) $display("  >>> ALL TESTS PASSED <<<");
        else $display("  >>> %0d TESTS FAILED <<<",fail_cnt);
        $display("============================================================\n");
        $finish;
    end
    initial begin #800000; $display("[TIMEOUT]"); $finish; end
endmodule
