//=============================================================================
// File: canfd_agent.sv
// Description: UVM Agent encapsulating CAN-FD Sequencer, Driver, and Monitor.
//=============================================================================

`ifndef CANFD_AGENT_SV
`define CANFD_AGENT_SV

class canfd_agent extends uvm_agent;
    `uvm_component_utils(canfd_agent)

    uvm_sequencer #(canfd_item) sequencer;
    canfd_driver                driver;
    canfd_monitor               monitor;
    uvm_analysis_port #(canfd_item) ap;

    function new(string name = "canfd_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);
        monitor = canfd_monitor::type_id::create("monitor", this);

        if (get_is_active() == UVM_ACTIVE) begin
            sequencer = uvm_sequencer#(canfd_item)::type_id::create("sequencer", this);
            driver    = canfd_driver::type_id::create("driver", this);
        end
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        monitor.item_collected_port.connect(ap);

        if (get_is_active() == UVM_ACTIVE) begin
            driver.seq_item_port.connect(sequencer.seq_item_export);
        end
    endfunction

endclass

`endif // CANFD_AGENT_SV
