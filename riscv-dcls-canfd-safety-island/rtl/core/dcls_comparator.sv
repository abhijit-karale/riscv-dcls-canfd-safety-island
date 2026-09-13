//=============================================================================
// File: dcls_comparator.sv
// Description: Dual-Core Lockstep (DCLS) Comparator Subsystem with
//              parameterized 2-cycle temporal diversity delay pipelines.
//              Provides ASIL-D diagnostic coverage (>99%) via cycle-accurate
//              lockstep retirement vector comparison.
//=============================================================================

`timescale 1ns/1ps

import rv32i_pkg::*;

module dcls_comparator #(
    parameter int DELAY_CYCLES = 2,
    parameter logic [31:0] BOOT_PC = 32'h0000_0000
)(
    input  logic                   clk,
    input  logic                   rst_n,

    // External Bus Interface (driven by Master Core)
    output logic [31:0]            imem_addr,
    output logic                   imem_req,
    input  logic [31:0]            imem_rdata,

    output logic [31:0]            dmem_addr,
    output logic [31:0]            dmem_wdata,
    output logic                   dmem_we,
    output logic [3:0]             dmem_be,
    output logic                   dmem_req,
    input  logic [31:0]            dmem_rdata,

    // Safety and Diagnostic Interface
    output logic                   safe_state_alarm,
    output logic [31:0]            fault_captured_pc,
    output logic [31:0]            fault_mismatch_mask,
    output logic [31:0]            fault_timestamp,
    input  logic                   alarm_clear_n, // Active-low synchronous clear

    // Hardware Fault Injection Unit (FIU)
    input  logic                   fiu_en,
    input  logic                   fiu_target_shadow, // 0: Master, 1: Shadow
    input  logic [1:0]             fiu_stage,
    input  logic [4:0]             fiu_bit_idx,
    input  logic [31:0]            fiu_mask
);

    //=========================================================================
    // Master Core Signals
    //=========================================================================
    logic [31:0]   m_imem_addr;
    logic          m_imem_req;
    logic [31:0]   m_dmem_addr;
    logic [31:0]   m_dmem_wdata;
    logic          m_dmem_we;
    logic [3:0]    m_dmem_be;
    logic          m_dmem_req;
    core_monitor_t m_monitor;

    // Direct driving of external bus by Master Core
    assign imem_addr  = m_imem_addr;
    assign imem_req   = m_imem_req;
    assign dmem_addr  = m_dmem_addr;
    assign dmem_wdata = m_dmem_wdata;
    assign dmem_we    = m_dmem_we;
    assign dmem_be    = m_dmem_be;
    assign dmem_req   = m_dmem_req;

    // Master Core FIU controls
    wire m_fiu_en = fiu_en && (!fiu_target_shadow);

    rv32i_core #(
        .BOOT_PC(BOOT_PC)
    ) u_master_core (
        .clk              (clk),
        .rst_n            (rst_n),
        .imem_addr        (m_imem_addr),
        .imem_req         (m_imem_req),
        .imem_rdata       (imem_rdata),
        .dmem_addr        (m_dmem_addr),
        .dmem_wdata       (m_dmem_wdata),
        .dmem_we          (m_dmem_we),
        .dmem_be          (m_dmem_be),
        .dmem_req         (m_dmem_req),
        .dmem_rdata       (dmem_rdata),
        .monitor_out      (m_monitor),
        .fiu_inject_en    (m_fiu_en),
        .fiu_target_stage (fiu_stage),
        .fiu_bit_index    (fiu_bit_idx),
        .fiu_mask         (fiu_mask)
    );

    //=========================================================================
    // Temporal Diversity Delay Pipelines (Z^-DELAY_CYCLES)
    //=========================================================================
    // Delay Shadow inputs so Shadow core runs delayed by DELAY_CYCLES
    logic [31:0] imem_rdata_dly [DELAY_CYCLES];
    logic [31:0] dmem_rdata_dly [DELAY_CYCLES];
    logic        rst_shadow_dly [DELAY_CYCLES];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < DELAY_CYCLES; i++) begin
                imem_rdata_dly[i] <= '0;
                dmem_rdata_dly[i] <= '0;
                rst_shadow_dly[i] <= 1'b0;
            end
        end else begin
            imem_rdata_dly[0] <= imem_rdata;
            dmem_rdata_dly[0] <= dmem_rdata;
            rst_shadow_dly[0] <= 1'b1;
            for (int i = 1; i < DELAY_CYCLES; i++) begin
                imem_rdata_dly[i] <= imem_rdata_dly[i-1];
                dmem_rdata_dly[i] <= dmem_rdata_dly[i-1];
                rst_shadow_dly[i] <= rst_shadow_dly[i-1];
            end
        end
    end

    wire [31:0] s_imem_rdata = imem_rdata_dly[DELAY_CYCLES-1];
    wire [31:0] s_dmem_rdata = dmem_rdata_dly[DELAY_CYCLES-1];
    wire        s_rst_n      = rst_n & rst_shadow_dly[DELAY_CYCLES-1];

    // Delay Master monitor outputs so they align with Shadow execution
    core_monitor_t m_monitor_dly [DELAY_CYCLES];
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < DELAY_CYCLES; i++) begin
                m_monitor_dly[i] <= '0;
            end
        end else begin
            m_monitor_dly[0] <= m_monitor;
            for (int i = 1; i < DELAY_CYCLES; i++) begin
                m_monitor_dly[i] <= m_monitor_dly[i-1];
            end
        end
    end

    wire core_monitor_t m_monitor_aligned = m_monitor_dly[DELAY_CYCLES-1];

    //=========================================================================
    // Shadow Core Signals & Instance
    //=========================================================================
    logic [31:0]   s_imem_addr;
    logic          s_imem_req;
    logic [31:0]   s_dmem_addr;
    logic [31:0]   s_dmem_wdata;
    logic          s_dmem_we;
    logic [3:0]    s_dmem_be;
    logic          s_dmem_req;
    core_monitor_t s_monitor;

    wire s_fiu_en = fiu_en && fiu_target_shadow;

    rv32i_core #(
        .BOOT_PC(BOOT_PC)
    ) u_shadow_core (
        .clk              (clk),
        .rst_n            (s_rst_n),
        .imem_addr        (s_imem_addr),
        .imem_req         (s_imem_req),
        .imem_rdata       (s_imem_rdata),
        .dmem_addr        (s_dmem_addr),
        .dmem_wdata       (s_dmem_wdata),
        .dmem_we          (s_dmem_we),
        .dmem_be          (s_dmem_be),
        .dmem_req         (s_dmem_req),
        .dmem_rdata       (s_dmem_rdata),
        .monitor_out      (s_monitor),
        .fiu_inject_en    (s_fiu_en),
        .fiu_target_stage (fiu_stage),
        .fiu_bit_index    (fiu_bit_idx),
        .fiu_mask         (fiu_mask)
    );

    //=========================================================================
    // Comparator & Lockstep Alarm Logic
    //=========================================================================
    logic [31:0] cycle_counter;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_counter <= '0;
        end else begin
            cycle_counter <= cycle_counter + 1'b1;
        end
    end

    // Divergence detection across execution outputs
    logic mismatch_detected;
    logic [31:0] mismatch_vector;

    always_comb begin
        mismatch_detected = 1'b0;
        mismatch_vector   = '0;

        // Only compare once shadow reset delay has elapsed and both cores are out of reset
        if (s_rst_n) begin
            if (m_monitor_aligned.valid != s_monitor.valid) begin
                mismatch_detected     = 1'b1;
                mismatch_vector[8]    = 1'b1; // Pipeline valid mismatch
            end
            if (m_monitor_aligned.valid || s_monitor.valid) begin
                if (m_monitor_aligned.pc_wb != s_monitor.pc_wb) begin
                    mismatch_detected     = 1'b1;
                    mismatch_vector[0]    = 1'b1; // PC mismatch
                end
            if (m_monitor_aligned.wb_reg_we != s_monitor.wb_reg_we) begin
                mismatch_detected     = 1'b1;
                mismatch_vector[1]    = 1'b1; // Regfile write enable mismatch
            end
            if (m_monitor_aligned.wb_reg_addr != s_monitor.wb_reg_addr) begin
                mismatch_detected     = 1'b1;
                mismatch_vector[2]    = 1'b1; // Regfile destination address mismatch
            end
            if (m_monitor_aligned.wb_reg_wdata != s_monitor.wb_reg_wdata) begin
                mismatch_detected     = 1'b1;
                mismatch_vector[3]    = 1'b1; // Regfile write data mismatch
            end
            if (m_monitor_aligned.mem_we != s_monitor.mem_we) begin
                mismatch_detected     = 1'b1;
                mismatch_vector[4]    = 1'b1; // Memory write enable mismatch
            end
            if (m_monitor_aligned.mem_addr != s_monitor.mem_addr) begin
                mismatch_detected     = 1'b1;
                mismatch_vector[5]    = 1'b1; // Memory address mismatch
            end
            if (m_monitor_aligned.mem_wdata != s_monitor.mem_wdata) begin
                mismatch_detected     = 1'b1;
                mismatch_vector[6]    = 1'b1; // Memory write data mismatch
            end
            if (m_monitor_aligned.mem_be != s_monitor.mem_be) begin
                mismatch_detected     = 1'b1;
                mismatch_vector[7]    = 1'b1; // Memory byte enable mismatch
            end
        end
        end
    end

    logic sticky_alarm;
    assign safe_state_alarm = sticky_alarm | mismatch_detected;

    // Sticky safe-state alarm latching
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sticky_alarm        <= 1'b0;
            fault_captured_pc   <= '0;
            fault_mismatch_mask <= '0;
            fault_timestamp     <= '0;
        end else if (!alarm_clear_n) begin
            sticky_alarm        <= 1'b0;
            fault_captured_pc   <= '0;
            fault_mismatch_mask <= '0;
            fault_timestamp     <= '0;
        end else if (mismatch_detected && !sticky_alarm) begin
            sticky_alarm        <= 1'b1;
            fault_captured_pc   <= m_monitor_aligned.pc_wb;
            fault_mismatch_mask <= mismatch_vector;
            fault_timestamp     <= cycle_counter;
        end
    end

endmodule
