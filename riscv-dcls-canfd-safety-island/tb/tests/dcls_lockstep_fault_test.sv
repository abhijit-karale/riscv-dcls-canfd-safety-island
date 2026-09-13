//=============================================================================
// File: dcls_lockstep_fault_test.sv
// Description: Primary ASIL-D verification test executing parallel CAN-FD
//              transactions and active pipeline fault injection to verify
//              the lockstep comparator and safe-state isolation.
//=============================================================================

`ifndef DCLS_LOCKSTEP_FAULT_TEST_SV
`define DCLS_LOCKSTEP_FAULT_TEST_SV

class dcls_lockstep_fault_test extends base_test;
    `uvm_component_utils(dcls_lockstep_fault_test)

    function new(string name = "dcls_lockstep_fault_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        canfd_base_seq      can_seq;
        fault_injection_seq fault_seq;

        phase.raise_objection(this, "Starting DCLS Lockstep Fault Test");
        `uvm_info(get_type_name(), "====== Executing DCLS Lockstep Fault Injection Test ======", UVM_LOW)

        can_seq   = canfd_base_seq::type_id::create("can_seq");
        fault_seq = fault_injection_seq::type_id::create("fault_seq");

        fork
            begin
                can_seq.start(env.can_ag.sequencer);
            end
            begin
                // Allow CAN traffic to initialize before triggering faults
                #200ns;
                fault_seq.start(env.fault_ag.sequencer);
            end
        join

        #1000ns;
        `uvm_info(get_type_name(), "====== Completed DCLS Lockstep Fault Injection Test ======", UVM_LOW)
        phase.drop_objection(this, "Completed DCLS Lockstep Fault Test");
    endtask

endclass

`endif // DCLS_LOCKSTEP_FAULT_TEST_SV
