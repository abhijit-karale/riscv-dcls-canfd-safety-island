//=============================================================================
// File: safety_island_env.sv
// Description: UVM Environment instantiating CAN-FD agent, Fault injection agent,
//              and Safety Scoreboard with end-to-end TLM connections.
//=============================================================================

`ifndef SAFETY_ISLAND_ENV_SV
`define SAFETY_ISLAND_ENV_SV

class safety_island_env extends uvm_env;
    `uvm_component_utils(safety_island_env)

    canfd_agent              can_ag;
    fault_agent              fault_ag;
    safety_island_scoreboard sb;

    function new(string name = "safety_island_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        can_ag   = canfd_agent::type_id::create("can_ag", this);
        fault_ag = fault_agent::type_id::create("fault_ag", this);
        sb       = safety_island_scoreboard::type_id::create("sb", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        // TLM Connections
        can_ag.ap.connect(sb.can_export);
        fault_ag.ap.connect(sb.fault_export);
    endfunction

endclass

`endif // SAFETY_ISLAND_ENV_SV
