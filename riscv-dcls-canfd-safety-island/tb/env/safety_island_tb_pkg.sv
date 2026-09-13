//=============================================================================
// File: safety_island_tb_pkg.sv
// Description: Master UVM 1.2 Verification Package for Safety Island Testbench.
//              Imports UVM library and includes all transaction items, agents,
//              sequences, scoreboards, environments, and tests.
//=============================================================================

`timescale 1ns/1ps

package safety_island_tb_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // Transaction items
    `include "../agents/canfd_agent/canfd_item.sv"
    `include "../agents/fault_agent/fault_item.sv"

    // Drivers & Monitors
    `include "../agents/canfd_agent/canfd_driver.sv"
    `include "../agents/canfd_agent/canfd_monitor.sv"
    `include "../agents/fault_agent/fault_driver.sv"

    // Agents
    `include "../agents/canfd_agent/canfd_agent.sv"
    `include "../agents/fault_agent/fault_agent.sv"

    // Sequences
    `include "../sequences/canfd_base_seq.sv"
    `include "../sequences/fault_injection_seq.sv"

    // Scoreboard & Environment
    `include "safety_island_scoreboard.sv"
    `include "safety_island_env.sv"

    // Test Cases
    `include "../tests/base_test.sv"
    `include "../tests/dcls_lockstep_fault_test.sv"

endpackage
