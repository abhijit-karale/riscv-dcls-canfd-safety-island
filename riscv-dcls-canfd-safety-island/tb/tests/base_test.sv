//=============================================================================
// File: base_test.sv
// Description: Base UVM Test establishing testbench environment, report verbosity,
//              and watchdog drain times.
//=============================================================================

`ifndef BASE_TEST_SV
`define BASE_TEST_SV

class base_test extends uvm_test;
    `uvm_component_utils(base_test)

    safety_island_env env;

    function new(string name = "base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = safety_island_env::type_id::create("env", this);
    endfunction

    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        uvm_top.print_topology();
    endfunction

    virtual task run_phase(uvm_phase phase);
        phase.phase_done.set_drain_time(this, 500ns);
    endtask

endclass

`endif // BASE_TEST_SV
