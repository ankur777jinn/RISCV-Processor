// DAC102 PROJECT - RV32I processor
// 24125006

`timescale 1ns / 1ps

module riscv_processor
  #(parameter RESET_ADDR = 32'h0,
    parameter ADDR_WIDTH  = 32)
   (input         clk,
    output [31:0] mem_addr,
    output [31:0] mem_wdata,
    output  [3:0] mem_wmask,
    input  [31:0] mem_rdata,
    output        mem_rstrb,
    input         mem_rbusy,
    input         mem_wbusy,
    input         reset);

  reg [31:0] RF [0:31];   // x0 always reads 0, handled in regA/regB wires below

  reg [31:0] PC;
  reg [31:0] IR;   

  reg [2:0] stage;
  localparam [2:0] FETCH=0, DECODE=1, EXEC=2, MEM_RD=3, MEM_WAIT=4, MEM_WR=5;

  reg [31:0] ld_addr, next_PC;
  reg [4:0]  ld_rd;
  reg [2:0]  ld_f3;

  wire [6:0] opcode = IR[6:0];
  wire [4:0] rd     = IR[11:7];
  wire [4:0] rs1    = IR[19:15];
  wire [4:0] rs2    = IR[24:20];
  wire [2:0] funct3 = IR[14:12];

  wire [31:0] regA = (rs1 == 0) ? 32'd0 : RF[rs1];
  wire [31:0] regB = (rs2 == 0) ? 32'd0 : RF[rs2];

  wire rtype  = (opcode == 7'h33);
  wire itype  = (opcode == 7'h13);
  wire load   = (opcode == 7'h03);
  wire store  = (opcode == 7'h23);
  wire branch = (opcode == 7'h63);
  wire jal    = (opcode == 7'h6F);
  wire jalr   = (opcode == 7'h67);
  wire lui    = (opcode == 7'h37);
  wire auipc  = (opcode == 7'h17);
  reg [31:0] imm;
  always @(*) begin
    case (opcode)
      7'h13, 7'h03, 7'h67:   // I type
        imm = {{20{IR[31]}}, IR[31:20]};
      7'h23:                  // S type (split across bits 11:7 and 31:25)
        imm = {{20{IR[31]}}, IR[31:25], IR[11:7]};
      7'h63:                  // B type
        imm = {{19{IR[31]}}, IR[31], IR[7], IR[30:25], IR[11:8], 1'b0};
      7'h37, 7'h17:           // U type
        imm = {IR[31:12], 12'd0};
      7'h6F:                  // J type (most scrambled one)
        imm = {{11{IR[31]}}, IR[31], IR[19:12], IR[20], IR[30:21], 1'b0};
      default: imm = 32'd0;
    endcase
  end

  // ALU
  reg  [31:0] alu_out;
  reg  [3:0]  alu_sel;
  wire [31:0] alu_A = auipc ? PC : regA;   // AUIPC adds to PC not a register
  wire [31:0] alu_B = rtype ? regB : imm;

  always @(*) begin
    if (lui)
      alu_sel = 4'd10;   // LUI doesn't add anything, just loads upper bits
    else if (auipc | load | store | jal | jalr)
      alu_sel = 4'd0;    // all need addition for address/target calculation
    else begin
      // R and I type - funct3 picks the operation, bit 30 distinguishes SUB/SRA
      case (funct3)
        3'b000:  alu_sel = (rtype & IR[30]) ? 4'd1 : 4'd0;
        3'b001:  alu_sel = 4'd5;
        3'b010:  alu_sel = 4'd8;
        3'b011:  alu_sel = 4'd9;
        3'b100:  alu_sel = 4'd4;
        3'b101:  alu_sel = IR[30] ? 4'd7 : 4'd6;
        3'b110:  alu_sel = 4'd3;
        3'b111:  alu_sel = 4'd2;
        default: alu_sel = 4'd0;
      endcase
    end
  end

  // 0=add 1=sub 2=and 3=or 4=xor 5=sll 6=srl 7=sra 8=slt 9=sltu 10=passB
  always @(*) begin
    case (alu_sel)
      4'd0:  alu_out = alu_A + alu_B;
      4'd1:  alu_out = alu_A - alu_B;
      4'd2:  alu_out = alu_A & alu_B;
      4'd3:  alu_out = alu_A | alu_B;
      4'd4:  alu_out = alu_A ^ alu_B;
      4'd5:  alu_out = alu_A << alu_B[4:0];
      4'd6:  alu_out = alu_A >> alu_B[4:0];
      4'd7:  alu_out = $signed(alu_A) >>> alu_B[4:0];   // arithmetic right shift
      4'd8:  alu_out = ($signed(alu_A) < $signed(alu_B)) ? 32'd1 : 32'd0;
      4'd9:  alu_out = (alu_A < alu_B) ? 32'd1 : 32'd0;
      4'd10: alu_out = alu_B;   // pass immediate through for LUI
      default: alu_out = 32'd0;
    endcase
  end

  // branch - funct3 encodes which comparison to do
  reg take_branch;
  always @(*) begin
    case (funct3)
      3'b000:  take_branch = (regA == regB);                        // BEQ
      3'b001:  take_branch = (regA != regB);                        // BNE
      3'b100:  take_branch = ($signed(regA) < $signed(regB));       // BLT
      3'b101:  take_branch = ($signed(regA) >= $signed(regB));      // BGE
      3'b110:  take_branch = (regA < regB);                         // BLTU
      3'b111:  take_branch = (regA >= regB);                        // BGEU
      default: take_branch = 1'b0;
    endcase
  end

  wire [31:0] PC4   = PC + 32'd4;
  wire [31:0] PCimm = PC + imm;
  wire [31:0] JALRT = (regA + imm) & ~32'd1;  // spec says clear lsb for JALR

  wire [31:0] nPC = jal                    ? PCimm :
                    jalr                   ? JALRT  :
                    (branch & take_branch) ? PCimm  :
                    PC4;

  // store formatting - for SB/SH we replicate data across all byte lanes
  // and use wmask to tell memory which byte(s) to actually write
  reg [31:0] st_data;
  reg [3:0]  st_mask;
  always @(*) begin
    case (funct3)
      3'b000: begin  // SB
        st_data = {4{regB[7:0]}};
        case (alu_out[1:0])
          2'b00: st_mask = 4'b0001;
          2'b01: st_mask = 4'b0010;
          2'b10: st_mask = 4'b0100;
          default: st_mask = 4'b1000;
        endcase
      end
      3'b001: begin  // SH
        st_data = {2{regB[15:0]}};
        st_mask = alu_out[1] ? 4'b1100 : 4'b0011;
      end
      default: begin  // SW - easy, just write the whole word
        st_data = regB;
        st_mask = 4'b1111;
      end
    endcase
  end

  wire [7:0]  byte_sel = mem_rdata >> {ld_addr[1:0], 3'b0};
  wire [15:0] half_sel = mem_rdata >> {ld_addr[1],   4'b0};

  reg [31:0] ld_val;
  always @(*) begin
    case (ld_f3)
      3'b000: ld_val = {{24{byte_sel[7]}},  byte_sel};   // LB  - sign extend byte
      3'b001: ld_val = {{16{half_sel[15]}}, half_sel};   // LH  - sign extend half
      3'b010: ld_val = mem_rdata;                         // LW
      3'b100: ld_val = {24'b0, byte_sel};                 // LBU - zero extend
      3'b101: ld_val = {16'b0, half_sel};                 // LHU - zero extend
      default: ld_val = mem_rdata;
    endcase
  end

  assign mem_addr  = (stage==FETCH || stage==DECODE) ? PC      :
                     (stage==MEM_RD || stage==MEM_WAIT) ? ld_addr :
                     alu_out;
  assign mem_rstrb = (stage == FETCH) || (stage == MEM_RD);
  assign mem_wdata = st_data;
  assign mem_wmask = (stage == MEM_WR) ? st_mask : 4'b0;

  wire rf_wr = rtype | itype | lui | auipc | jal | jalr;
  wire [31:0] wb_val = (jal | jalr) ? PC4 : alu_out;  // JAL/JALR write return addr

  integer i;

  always @(posedge clk) begin
    if (!reset) begin
      PC    <= RESET_ADDR;
      stage <= FETCH;
      IR    <= 32'h00000013;  // NOP on reset
      for (i = 0; i < 32; i = i+1) RF[i] <= 32'd0;
      ld_addr <= 0; ld_rd <= 0; ld_f3 <= 0; next_PC <= 0;
    end
    else begin
      case (stage)

        FETCH: begin
          stage <= DECODE;
        end

        DECODE: begin
          if (!mem_rbusy) begin
            IR    <= mem_rdata;
            stage <= EXEC;
          end
        end

        EXEC: begin
          if (load) begin
            ld_addr <= alu_out;
            ld_f3   <= funct3;
            ld_rd   <= rd;
            next_PC <= nPC;
            stage   <= MEM_RD;
          end
          else if (store) begin
            next_PC <= nPC;
            stage   <= MEM_WR;
          end
          else begin
            if (rf_wr && rd != 5'd0)
              RF[rd] <= wb_val;
            PC    <= nPC;
            stage <= FETCH;
          end
        end

        MEM_RD: begin
          stage <= MEM_WAIT;
        end

        MEM_WAIT: begin
          if (!mem_rbusy) begin
            if (ld_rd != 5'd0) RF[ld_rd] <= ld_val;
            PC    <= next_PC;
            stage <= FETCH;
          end
        end

        MEM_WR: begin
          if (!mem_wbusy) begin
            PC    <= next_PC;
            stage <= FETCH;
          end
        end

        default: stage <= FETCH;

      endcase
    end
  end

endmodule
