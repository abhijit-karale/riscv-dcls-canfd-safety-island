//=============================================================================
// File: rv32i_core.sv
// Description: Synthesizable 5-stage pipelined RV32I RISC-V processor core
//              with data forwarding, hazard detection, structured lockstep
//              diagnostic bus, and hardware fault injection interface.
// Standard: RV32I Base Integer Instruction Set (Unprivileged Spec 20191213)
// Architecture: IF -> ID -> EX -> MEM -> WB
//=============================================================================

`timescale 1ns/1ps

package rv32i_pkg;
    // Opcodes
    localparam logic [6:0] OPC_OP_IMM = 7'b0010011;
    localparam logic [6:0] OPC_LUI    = 7'b0110111;
    localparam logic [6:0] OPC_AUIPC  = 7'b0010111;
    localparam logic [6:0] OPC_OP      = 7'b0110011;
    localparam logic [6:0] OPC_JAL     = 7'b1101111;
    localparam logic [6:0] OPC_JALR    = 7'b1100111;
    localparam logic [6:0] OPC_BRANCH  = 7'b1100011;
    localparam logic [6:0] OPC_LOAD    = 7'b0000011;
    localparam logic [6:0] OPC_STORE   = 7'b0100011;

    // ALU Operations
    typedef enum logic [3:0] {
        ALU_ADD  = 4'b0000,
        ALU_SUB  = 4'b1000,
        ALU_SLL  = 4'b0001,
        ALU_SLT  = 4'b0010,
        ALU_SLTU = 4'b0011,
        ALU_XOR  = 4'b0100,
        ALU_SRL  = 4'b0101,
        ALU_SRA  = 4'b1101,
        ALU_OR   = 4'b0110,
        ALU_AND  = 4'b0111
    } alu_op_e;

    // Diagnostic bus structure for cycle-accurate lockstep validation
    typedef struct packed {
        logic [31:0] pc_wb;
        logic        wb_reg_we;
        logic [4:0]  wb_reg_addr;
        logic [31:0] wb_reg_wdata;
        logic [31:0] mem_addr;
        logic [31:0] mem_wdata;
        logic        mem_we;
        logic [3:0]  mem_be;
        logic        valid;
    } core_monitor_t;
endpackage

import rv32i_pkg::*;

module rv32i_core #(
    parameter logic [31:0] BOOT_PC = 32'h0000_0000
)(
    input  logic                   clk,
    input  logic                   rst_n,

    // Instruction Memory Interface
    output logic [31:0]            imem_addr,
    output logic                   imem_req,
    input  logic [31:0]            imem_rdata,

    // Data Memory Interface
    output logic [31:0]            dmem_addr,
    output logic [31:0]            dmem_wdata,
    output logic                   dmem_we,
    output logic [3:0]             dmem_be,
    output logic                   dmem_req,
    input  logic [31:0]            dmem_rdata,

    // Lockstep Diagnostic Bus
    output core_monitor_t          monitor_out,

    // Fault Injection Unit (FIU) Target Port
    input  logic                   fiu_inject_en,
    input  logic [1:0]             fiu_target_stage, // 0:ID, 1:EX, 2:MEM, 3:WB
    input  logic [4:0]             fiu_bit_index,
    input  logic [31:0]            fiu_mask
);

    //=========================================================================
    // 1. Pipeline Registers Definitions
    //=========================================================================
    
    // IF/ID
    typedef struct packed {
        logic [31:0] pc;
        logic [31:0] instr;
        logic        valid;
    } if_id_reg_t;

    // ID/EX
    typedef struct packed {
        logic [31:0] pc;
        logic [31:0] rs1_data;
        logic [31:0] rs2_data;
        logic [31:0] imm;
        logic [4:0]  rs1_addr;
        logic [4:0]  rs2_addr;
        logic [4:0]  rd_addr;
        alu_op_e     alu_op;
        logic        alu_src_imm;
        logic        mem_read;
        logic        mem_write;
        logic [2:0]  mem_funct3;
        logic        reg_write;
        logic        is_jump;
        logic        is_jalr;
        logic        is_branch;
        logic [2:0]  branch_funct3;
        logic        valid;
    } id_ex_reg_t;

    // EX/MEM
    typedef struct packed {
        logic [31:0] pc;
        logic [31:0] alu_result;
        logic [31:0] rs2_data;
        logic [4:0]  rd_addr;
        logic        mem_read;
        logic        mem_write;
        logic [2:0]  mem_funct3;
        logic        reg_write;
        logic        valid;
    } ex_mem_reg_t;

    // MEM/WB
    typedef struct packed {
        logic [31:0] pc;
        logic [31:0] alu_result;
        logic [31:0] mem_rdata;
        logic [4:0]  rd_addr;
        logic        mem_read;
        logic        reg_write;
        logic        valid;
    } mem_wb_reg_t;

    if_id_reg_t  if_id_q,  if_id_d;
    id_ex_reg_t  id_ex_q,  id_ex_d;
    ex_mem_reg_t ex_mem_q, ex_mem_d;
    mem_wb_reg_t mem_wb_q, mem_wb_d;

    // Control hazard signals
    logic        stall_if_id;
    logic        flush_if_id;
    logic        flush_id_ex;
    logic        branch_taken;
    logic [31:0] branch_target_pc;

    // Register File (32 x 32)
    logic [31:0] regfile [0:31];

    //=========================================================================
    // 2. IF Stage (Instruction Fetch)
    //=========================================================================
    logic [31:0] pc_q, pc_next;

    always_comb begin
        if (branch_taken) begin
            pc_next = branch_target_pc;
        end else if (stall_if_id) begin
            pc_next = pc_q;
        end else begin
            pc_next = pc_q + 32'd4;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_q <= BOOT_PC;
        end else begin
            pc_q <= pc_next;
        end
    end

    assign imem_addr = pc_q;
    assign imem_req  = rst_n;

    // IF/ID Pipeline Register with fault injection (Stage 0)
    if_id_reg_t if_id_injected;
    always_comb begin
        if_id_d.pc    = pc_q;
        if_id_d.instr = imem_rdata;
        if_id_d.valid = rst_n && !flush_if_id;

        if_id_injected = if_id_d;
        if (fiu_inject_en && (fiu_target_stage == 2'd0)) begin
            if_id_injected.instr = if_id_injected.instr ^ fiu_mask;
            if_id_injected.pc    = if_id_injected.pc    ^ fiu_mask;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            if_id_q <= '0;
        end else if (flush_if_id) begin
            if_id_q <= '0;
        end else if (!stall_if_id) begin
            if_id_q <= if_id_injected;
        end
    end

    //=========================================================================
    // 3. ID Stage (Instruction Decode & Register Read)
    //=========================================================================
    wire [6:0] id_opcode = if_id_q.instr[6:0];
    wire [4:0] id_rd     = if_id_q.instr[11:7];
    wire [2:0] id_funct3 = if_id_q.instr[14:12];
    wire [4:0] id_rs1    = if_id_q.instr[19:15];
    wire [4:0] id_rs2    = if_id_q.instr[24:20];
    wire [6:0] id_funct7 = if_id_q.instr[31:25];

    // Immediate generation
    logic [31:0] imm_i, imm_s, imm_b, imm_u, imm_j, id_imm;
    assign imm_i = {{20{if_id_q.instr[31]}}, if_id_q.instr[31:20]};
    assign imm_s = {{20{if_id_q.instr[31]}}, if_id_q.instr[31:25], if_id_q.instr[11:7]};
    assign imm_b = {{19{if_id_q.instr[31]}}, if_id_q.instr[31], if_id_q.instr[7], if_id_q.instr[30:25], if_id_q.instr[11:8], 1'b0};
    assign imm_u = {if_id_q.instr[31:12], 12'h000};
    assign imm_j = {{11{if_id_q.instr[31]}}, if_id_q.instr[31], if_id_q.instr[19:12], if_id_q.instr[20], if_id_q.instr[30:21], 1'b0};

    // Forwarding to ID stage for register reads with internal bypass
    logic [31:0] rf_rs1_val, rf_rs2_val;
    logic [31:0] wb_final_data;

    // Regfile Read with write-through bypass
    assign rf_rs1_val = (id_rs1 == 5'd0) ? 32'd0 :
                        (mem_wb_q.reg_write && (mem_wb_q.rd_addr == id_rs1)) ? wb_final_data :
                        regfile[id_rs1];

    assign rf_rs2_val = (id_rs2 == 5'd0) ? 32'd0 :
                        (mem_wb_q.reg_write && (mem_wb_q.rd_addr == id_rs2)) ? wb_final_data :
                        regfile[id_rs2];

    // Decode Logic
    always_comb begin
        id_ex_d = '0;
        id_ex_d.pc        = if_id_q.pc;
        id_ex_d.rs1_data  = rf_rs1_val;
        id_ex_d.rs2_data  = rf_rs2_val;
        id_ex_d.rs1_addr  = id_rs1;
        id_ex_d.rs2_addr  = id_rs2;
        id_ex_d.rd_addr   = id_rd;
        id_ex_d.valid     = if_id_q.valid && !flush_if_id;

        case (id_opcode)
            OPC_OP: begin
                id_ex_d.reg_write   = 1'b1;
                id_ex_d.alu_src_imm = 1'b0;
                id_imm              = 32'd0;
                case (id_funct3)
                    3'b000: id_ex_d.alu_op = (id_funct7[5]) ? ALU_SUB : ALU_ADD;
                    3'b001: id_ex_d.alu_op = ALU_SLL;
                    3'b010: id_ex_d.alu_op = ALU_SLT;
                    3'b011: id_ex_d.alu_op = ALU_SLTU;
                    3'b100: id_ex_d.alu_op = ALU_XOR;
                    3'b101: id_ex_d.alu_op = (id_funct7[5]) ? ALU_SRA : ALU_SRL;
                    3'b110: id_ex_d.alu_op = ALU_OR;
                    3'b111: id_ex_d.alu_op = ALU_AND;
                    default: id_ex_d.alu_op = ALU_ADD;
                endcase
            end

            OPC_OP_IMM: begin
                id_ex_d.reg_write   = 1'b1;
                id_ex_d.alu_src_imm = 1'b1;
                id_imm              = imm_i;
                case (id_funct3)
                    3'b000: id_ex_d.alu_op = ALU_ADD;
                    3'b001: id_ex_d.alu_op = ALU_SLL;
                    3'b010: id_ex_d.alu_op = ALU_SLT;
                    3'b011: id_ex_d.alu_op = ALU_SLTU;
                    3'b100: id_ex_d.alu_op = ALU_XOR;
                    3'b101: id_ex_d.alu_op = (id_funct7[5]) ? ALU_SRA : ALU_SRL;
                    3'b110: id_ex_d.alu_op = ALU_OR;
                    3'b111: id_ex_d.alu_op = ALU_AND;
                    default: id_ex_d.alu_op = ALU_ADD;
                endcase
            end

            OPC_LUI: begin
                id_ex_d.reg_write   = 1'b1;
                id_ex_d.alu_src_imm = 1'b1;
                id_imm              = imm_u;
                id_ex_d.alu_op      = ALU_ADD;
                id_ex_d.rs1_data    = 32'd0;
            end

            OPC_AUIPC: begin
                id_ex_d.reg_write   = 1'b1;
                id_ex_d.alu_src_imm = 1'b1;
                id_imm              = imm_u;
                id_ex_d.alu_op      = ALU_ADD;
                id_ex_d.rs1_data    = if_id_q.pc;
            end

            OPC_LOAD: begin
                id_ex_d.reg_write   = 1'b1;
                id_ex_d.mem_read    = 1'b1;
                id_ex_d.alu_src_imm = 1'b1;
                id_imm              = imm_i;
                id_ex_d.alu_op      = ALU_ADD;
                id_ex_d.mem_funct3  = id_funct3;
            end

            OPC_STORE: begin
                id_ex_d.mem_write   = 1'b1;
                id_ex_d.alu_src_imm = 1'b1;
                id_imm              = imm_s;
                id_ex_d.alu_op      = ALU_ADD;
                id_ex_d.mem_funct3  = id_funct3;
            end

            OPC_BRANCH: begin
                id_ex_d.is_branch     = 1'b1;
                id_ex_d.branch_funct3 = id_funct3;
                id_imm                = imm_b;
                id_ex_d.alu_op        = ALU_ADD;
            end

            OPC_JAL: begin
                id_ex_d.is_jump     = 1'b1;
                id_ex_d.reg_write   = 1'b1;
                id_imm              = imm_j;
            end

            OPC_JALR: begin
                id_ex_d.is_jump     = 1'b1;
                id_ex_d.is_jalr     = 1'b1;
                id_ex_d.reg_write   = 1'b1;
                id_imm              = imm_i;
            end

            default: begin
                id_imm = 32'd0;
            end
        endcase

        id_ex_d.imm = id_imm;
    end

    // Load-Use Hazard Detection
    always_comb begin
        stall_if_id = 1'b0;
        flush_id_ex = 1'b0;
        if (id_ex_q.mem_read && (id_ex_q.rd_addr != 5'd0) &&
            ((id_ex_q.rd_addr == id_rs1) || (id_ex_q.rd_addr == id_rs2))) begin
            stall_if_id = 1'b1;
            flush_id_ex = 1'b1;
        end
    end

    // Fault injection into ID/EX stage register (Stage 1)
    id_ex_reg_t id_ex_injected;
    always_comb begin
        id_ex_injected = id_ex_d;
        if (fiu_inject_en && (fiu_target_stage == 2'd1)) begin
            id_ex_injected.rs1_data = id_ex_injected.rs1_data ^ fiu_mask;
            id_ex_injected.pc       = id_ex_injected.pc       ^ fiu_mask;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            id_ex_q <= '0;
        end else if (flush_id_ex || branch_taken) begin
            id_ex_q <= '0;
        end else begin
            id_ex_q <= id_ex_injected;
        end
    end

    //=========================================================================
    // 4. EX Stage (Execute & ALU & Branch Resolution)
    //=========================================================================
    logic [31:0] alu_in_a, alu_in_b;
    logic [31:0] ex_rs2_forwarded;
    logic [31:0] alu_result;

    // Forwarding Unit
    always_comb begin
        // Forward A
        if (ex_mem_q.reg_write && (ex_mem_q.rd_addr != 5'd0) && (ex_mem_q.rd_addr == id_ex_q.rs1_addr)) begin
            alu_in_a = ex_mem_q.alu_result;
        end else if (mem_wb_q.reg_write && (mem_wb_q.rd_addr != 5'd0) && (mem_wb_q.rd_addr == id_ex_q.rs1_addr)) begin
            alu_in_a = wb_final_data;
        end else begin
            alu_in_a = id_ex_q.rs1_data;
        end

        // Forward B
        if (ex_mem_q.reg_write && (ex_mem_q.rd_addr != 5'd0) && (ex_mem_q.rd_addr == id_ex_q.rs2_addr)) begin
            ex_rs2_forwarded = ex_mem_q.alu_result;
        end else if (mem_wb_q.reg_write && (mem_wb_q.rd_addr != 5'd0) && (mem_wb_q.rd_addr == id_ex_q.rs2_addr)) begin
            ex_rs2_forwarded = wb_final_data;
        end else begin
            ex_rs2_forwarded = id_ex_q.rs2_data;
        end

        alu_in_b = id_ex_q.alu_src_imm ? id_ex_q.imm : ex_rs2_forwarded;
    end

    // ALU Core
    always_comb begin
        case (id_ex_q.alu_op)
            ALU_ADD:  alu_result = alu_in_a + alu_in_b;
            ALU_SUB:  alu_result = alu_in_a - alu_in_b;
            ALU_SLL:  alu_result = alu_in_a << alu_in_b[4:0];
            ALU_SLT:  alu_result = ($signed(alu_in_a) < $signed(alu_in_b)) ? 32'd1 : 32'd0;
            ALU_SLTU: alu_result = (alu_in_a < alu_in_b) ? 32'd1 : 32'd0;
            ALU_XOR:  alu_result = alu_in_a ^ alu_in_b;
            ALU_SRL:  alu_result = alu_in_a >> alu_in_b[4:0];
            ALU_SRA:  alu_result = $signed(alu_in_a) >>> alu_in_b[4:0];
            ALU_OR:   alu_result = alu_in_a | alu_in_b;
            ALU_AND:  alu_result = alu_in_a & alu_in_b;
            default:  alu_result = alu_in_a + alu_in_b;
        endcase
    end

    // Branch & Jump Resolution
    always_comb begin
        branch_taken = 1'b0;
        branch_target_pc = 32'd0;

        if (id_ex_q.valid) begin
            if (id_ex_q.is_jump) begin
                branch_taken = 1'b1;
                if (id_ex_q.is_jalr) begin
                    branch_target_pc = (alu_in_a + id_ex_q.imm) & ~32'd1;
                end else begin
                    branch_target_pc = id_ex_q.pc + id_ex_q.imm;
                end
            end else if (id_ex_q.is_branch) begin
                case (id_ex_q.branch_funct3)
                    3'b000: branch_taken = (alu_in_a == ex_rs2_forwarded);                         // BEQ
                    3'b001: branch_taken = (alu_in_a != ex_rs2_forwarded);                         // BNE
                    3'b100: branch_taken = ($signed(alu_in_a) < $signed(ex_rs2_forwarded));        // BLT
                    3'b101: branch_taken = ($signed(alu_in_a) >= $signed(ex_rs2_forwarded));       // BGE
                    3'b110: branch_taken = (alu_in_a < ex_rs2_forwarded);                         // BLTU
                    3'b111: branch_taken = (alu_in_a >= ex_rs2_forwarded);                        // BGEU
                    default: branch_taken = 1'b0;
                endcase
                branch_target_pc = id_ex_q.pc + id_ex_q.imm;
            end
        end
    end

    assign flush_if_id = branch_taken;

    // EX/MEM Pipeline Register
    always_comb begin
        ex_mem_d.pc         = id_ex_q.pc;
        ex_mem_d.alu_result = id_ex_q.is_jump ? (id_ex_q.pc + 32'd4) : alu_result;
        ex_mem_d.rs2_data   = ex_rs2_forwarded;
        ex_mem_d.rd_addr    = id_ex_q.rd_addr;
        ex_mem_d.mem_read   = id_ex_q.mem_read;
        ex_mem_d.mem_write  = id_ex_q.mem_write;
        ex_mem_d.mem_funct3 = id_ex_q.mem_funct3;
        ex_mem_d.reg_write  = id_ex_q.reg_write;
        ex_mem_d.valid      = id_ex_q.valid;
    end

    // Fault injection into EX/MEM stage (Stage 2)
    ex_mem_reg_t ex_mem_injected;
    always_comb begin
        ex_mem_injected = ex_mem_d;
        if (fiu_inject_en && (fiu_target_stage == 2'd2)) begin
            ex_mem_injected.alu_result = ex_mem_injected.alu_result ^ fiu_mask;
            ex_mem_injected.pc         = ex_mem_injected.pc         ^ fiu_mask;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex_mem_q <= '0;
        end else begin
            ex_mem_q <= ex_mem_injected;
        end
    end

    //=========================================================================
    // 5. MEM Stage (Data Memory Access)
    //=========================================================================
    assign dmem_addr = ex_mem_q.alu_result;
    assign dmem_req  = ex_mem_q.valid && (ex_mem_q.mem_read || ex_mem_q.mem_write);
    assign dmem_we   = ex_mem_q.valid && ex_mem_q.mem_write;

    // Store formatting (SB, SH, SW)
    always_comb begin
        dmem_wdata = 32'd0;
        dmem_be    = 4'b0000;
        case (ex_mem_q.mem_funct3)
            3'b000: begin // SB
                case (ex_mem_q.alu_result[1:0])
                    2'b00: begin dmem_wdata[7:0]   = ex_mem_q.rs2_data[7:0]; dmem_be = 4'b0001; end
                    2'b01: begin dmem_wdata[15:8]  = ex_mem_q.rs2_data[7:0]; dmem_be = 4'b0010; end
                    2'b10: begin dmem_wdata[23:16] = ex_mem_q.rs2_data[7:0]; dmem_be = 4'b0100; end
                    2'b11: begin dmem_wdata[31:24] = ex_mem_q.rs2_data[7:0]; dmem_be = 4'b1000; end
                endcase
            end
            3'b001: begin // SH
                if (ex_mem_q.alu_result[1]) begin
                    dmem_wdata[31:16] = ex_mem_q.rs2_data[15:0];
                    dmem_be = 4'b1100;
                end else begin
                    dmem_wdata[15:0]  = ex_mem_q.rs2_data[15:0];
                    dmem_be = 4'b0011;
                end
            end
            3'b010: begin // SW
                dmem_wdata = ex_mem_q.rs2_data;
                dmem_be    = 4'b1111;
            end
            default: begin
                dmem_wdata = ex_mem_q.rs2_data;
                dmem_be    = 4'b1111;
            end
        endcase
    end

    // Load sign/zero extension
    logic [31:0] mem_rdata_formatted;
    always_comb begin
        case (ex_mem_q.mem_funct3)
            3'b000: begin // LB
                case (ex_mem_q.alu_result[1:0])
                    2'b00: mem_rdata_formatted = {{24{dmem_rdata[7]}},  dmem_rdata[7:0]};
                    2'b01: mem_rdata_formatted = {{24{dmem_rdata[15]}}, dmem_rdata[15:8]};
                    2'b10: mem_rdata_formatted = {{24{dmem_rdata[23]}}, dmem_rdata[23:16]};
                    2'b11: mem_rdata_formatted = {{24{dmem_rdata[31]}}, dmem_rdata[31:24]};
                endcase
            end
            3'b001: begin // LH
                if (ex_mem_q.alu_result[1]) begin
                    mem_rdata_formatted = {{16{dmem_rdata[31]}}, dmem_rdata[31:16]};
                end else begin
                    mem_rdata_formatted = {{16{dmem_rdata[15]}}, dmem_rdata[15:0]};
                end
            end
            3'b010: mem_rdata_formatted = dmem_rdata; // LW
            3'b100: begin // LBU
                case (ex_mem_q.alu_result[1:0])
                    2'b00: mem_rdata_formatted = {24'd0, dmem_rdata[7:0]};
                    2'b01: mem_rdata_formatted = {24'd0, dmem_rdata[15:8]};
                    2'b10: mem_rdata_formatted = {24'd0, dmem_rdata[23:16]};
                    2'b11: mem_rdata_formatted = {24'd0, dmem_rdata[31:24]};
                endcase
            end
            3'b101: begin // LHU
                if (ex_mem_q.alu_result[1]) begin
                    mem_rdata_formatted = {16'd0, dmem_rdata[31:16]};
                end else begin
                    mem_rdata_formatted = {16'd0, dmem_rdata[15:0]};
                end
            end
            default: mem_rdata_formatted = dmem_rdata;
        endcase
    end

    // MEM/WB Pipeline Register
    always_comb begin
        mem_wb_d.pc         = ex_mem_q.pc;
        mem_wb_d.alu_result = ex_mem_q.alu_result;
        mem_wb_d.mem_rdata  = mem_rdata_formatted;
        mem_wb_d.rd_addr    = ex_mem_q.rd_addr;
        mem_wb_d.mem_read   = ex_mem_q.mem_read;
        mem_wb_d.reg_write  = ex_mem_q.reg_write;
        mem_wb_d.valid      = ex_mem_q.valid;
    end

    // Fault injection into MEM/WB stage (Stage 3)
    mem_wb_reg_t mem_wb_injected;
    always_comb begin
        mem_wb_injected = mem_wb_d;
        if (fiu_inject_en && (fiu_target_stage == 2'd3)) begin
            mem_wb_injected.alu_result = mem_wb_injected.alu_result ^ fiu_mask;
            mem_wb_injected.mem_rdata  = mem_wb_injected.mem_rdata  ^ fiu_mask;
            mem_wb_injected.pc         = mem_wb_injected.pc         ^ fiu_mask;
            mem_wb_injected.valid      = 1'b1;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_wb_q <= '0;
        end else begin
            mem_wb_q <= mem_wb_injected;
        end
    end

    //=========================================================================
    // 6. WB Stage (Write Back & Register File Commit)
    //=========================================================================
    wire [31:0] wb_raw_data = mem_wb_q.mem_read ? mem_wb_q.mem_rdata : mem_wb_q.alu_result;
    assign wb_final_data = (fiu_inject_en && (fiu_target_stage == 2'd3)) ? (wb_raw_data ^ fiu_mask) : wb_raw_data;

    // Register File Commit
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int r = 0; r < 32; r++) begin
                regfile[r] <= 32'd0;
            end
        end else if (mem_wb_q.valid && mem_wb_q.reg_write && (mem_wb_q.rd_addr != 5'd0)) begin
            regfile[mem_wb_q.rd_addr] <= wb_final_data;
        end
    end

    //=========================================================================
    // 7. Lockstep Diagnostic Bus Assignment
    //=========================================================================
    always_comb begin
        monitor_out.pc_wb       = mem_wb_q.pc;
        monitor_out.wb_reg_we   = mem_wb_q.valid && mem_wb_q.reg_write && (mem_wb_q.rd_addr != 5'd0);
        monitor_out.wb_reg_addr = mem_wb_q.rd_addr;
        monitor_out.wb_reg_wdata= wb_final_data;
        monitor_out.mem_addr    = ex_mem_q.alu_result;
        monitor_out.mem_wdata   = dmem_wdata;
        monitor_out.mem_we      = dmem_we;
        monitor_out.mem_be      = dmem_be;
        monitor_out.valid       = mem_wb_q.valid;
    end

endmodule
