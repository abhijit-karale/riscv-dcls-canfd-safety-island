//=============================================================================
// File: tb_top.sv
// Description: Top-level Testbench Harness for Automotive Safety Island.
//              Generates 200 MHz Core and 40 MHz CAN asynchronous clocks,
//              instantiates interface, DUT, binds assertions, and initiates
//              UVM test execution via run_test().
//=============================================================================

`timescale 1ns/1ps

import uvm_pkg::*;
`include "uvm_macros.svh"
import safety_island_tb_pkg::*;

module tb_top;

    // Clock and Reset Generation
    logic clk_core;
    logic clk_can;
    logic rst_core_n;
    logic rst_can_n;

    // 200 MHz Core Domain Clock (Period = 5.0 ns)
    initial clk_core = 1'b0;
    always #2.5ns clk_core = ~clk_core;

    // 40 MHz CAN Domain Clock (Period = 25.0 ns)
    initial clk_can = 1'b0;
    always #12.5ns clk_can = ~clk_can;

    // Reset Sequence
    initial begin
        rst_core_n = 1'b0;
        rst_can_n  = 1'b0;
        #50ns;
        rst_core_n = 1'b1;
        #50ns;
        rst_can_n  = 1'b1;
    end

    // Interface Instance
    safety_island_if dut_if (
        .clk_core   (clk_core),
        .clk_can    (clk_can),
        .rst_core_n (rst_core_n),
        .rst_can_n  (rst_can_n)
    );

    // DUT (Safety Island Top) Instance
    safety_island_top #(
        .MEM_SIZE_WORDS(1024)
    ) u_dut (
        .clk_core              (clk_core),
        .rst_core_n            (rst_core_n),
        .clk_can               (clk_can),
        .rst_can_n             (rst_can_n),
        .can_tx                (dut_if.can_tx),
        .can_rx                (dut_if.can_rx),
        .safe_state_alarm_o    (dut_if.safe_state_alarm),
        .fault_status_o        (dut_if.fault_status),
        .fault_pc_o            (dut_if.fault_pc),
        .alarm_clear_n         (dut_if.alarm_clear_n),
        .fiu_ext_en            (dut_if.fiu_en),
        .fiu_ext_target_shadow (dut_if.fiu_target_shadow),
        .fiu_ext_stage         (dut_if.fiu_stage),
        .fiu_ext_bit_idx       (dut_if.fiu_bit_idx),
        .fiu_ext_mask          (dut_if.fiu_mask)
    );

    // Formal Assertions Binding Module Instance
    dcls_assertions_bind u_assertions_bind();

    // Initial UVM Setup and Execution
    initial begin
        // Store interface handle into UVM config db
        uvm_config_db#(virtual safety_island_if)::set(null, "*", "vif", dut_if);

        // Optional VCD waveform dump
        if ($test$plusargs("DUMP_VCD")) begin
            $dumpfile("sim_trace.vcd");
            $dumpvars(0, tb_top);
        end

        // Start selected test
        run_test();
    end

endmodule
