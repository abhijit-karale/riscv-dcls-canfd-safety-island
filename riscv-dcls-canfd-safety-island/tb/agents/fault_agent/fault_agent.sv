//=============================================================================
// File: fault_agent.sv
// Description: UVM Agent for Hardware Fault Injection Unit (FIU).
//=============================================================================

`ifndef FAULT_AGENT_SV
`define FAULT_AGENT_SV

class fault_agent extends uvm_agent;
    `uvm_component_utils(fault_agent)

    uvm_sequencer #(fault_item) sequencer;
    fault_driver                driver;
    uvm_analysis_port #(fault_item) ap;

    function new(string name = "fault_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);

        if (get_is_active() == UVM_ACTIVE) begin
            sequencer = uvm_sequencer#(fault_item)::type_id::create("sequencer", this);
            driver    = fault_driver::type_id::create("driver", this);
        end
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if (get_is_active() == UVM_ACTIVE) begin
            driver.seq_item_port.connect(sequencer.seq_item_export);
            driver.fault_ap.connect(ap);
        end
    endfunction

endclass

`endif // FAULT_AGENT_SV
