//=============================================================================
// File: safety_island_if.sv
// Description: SystemVerilog Interface for Automotive Safety Island Testbench.
//              Provides physical CAN bus signals, hardware fault injection
//              signals, and ASIL-D safe-state alarm monitoring signals.
//=============================================================================

`timescale 1ns/1ps

interface safety_island_if (
    input logic clk_core,
    input logic clk_can,
    input logic rst_core_n,
    input logic rst_can_n
);

    // CAN Bus Physical Signals
    logic        can_tx;
    logic        can_rx;

    // Safety and Alarm Signals
    logic        safe_state_alarm;
    logic [31:0] fault_status;
    logic [31:0] fault_pc;
    logic        alarm_clear_n;

    // Fault Injection Unit (FIU) Signals
    logic        fiu_en;
    logic        fiu_target_shadow;
    logic [1:0]  fiu_stage;
    logic [4:0]  fiu_bit_idx;
    logic [31:0] fiu_mask;

    // Clocking block for CAN Agent Driver
    clocking can_drv_cb @(posedge clk_can);
        default input #1ns output #1ns;
        output can_rx;
        input  can_tx;
    endclocking

    // Clocking block for CAN Agent Monitor
    clocking can_mon_cb @(posedge clk_can);
        default input #1ns output #1ns;
        input can_tx;
        input can_rx;
    endclocking

    // Clocking block for Fault Agent Driver (Core Domain)
    clocking fault_drv_cb @(posedge clk_core);
        default input #1ns output #1ns;
        output fiu_en;
        output fiu_target_shadow;
        output fiu_stage;
        output fiu_bit_idx;
        output fiu_mask;
        output alarm_clear_n;
        input  safe_state_alarm;
        input  fault_status;
        input  fault_pc;
    endclocking

    // Clocking block for Safety Alarm Monitor (Core Domain)
    clocking safety_mon_cb @(posedge clk_core);
        default input #1ns output #1ns;
        input safe_state_alarm;
        input fault_status;
        input fault_pc;
        input fiu_en;
    endclocking

    modport can_drv    (clocking can_drv_cb);
    modport can_mon    (clocking can_mon_cb);
    modport fault_drv  (clocking fault_drv_cb);
    modport safety_mon (clocking safety_mon_cb);

endinterface
