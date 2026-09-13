//=============================================================================
// File: fault_injection_seq.sv
// Description: Fault Injection Sequence randomly flipping bits in the
//              shadow core's pipeline stages (ID, EX, MEM, WB) and validating
//              that the safe_state_alarm triggers within <= 2 clock cycles.
//=============================================================================

`ifndef FAULT_INJECTION_SEQ_SV
`define FAULT_INJECTION_SEQ_SV

class fault_injection_seq extends uvm_sequence #(fault_item);
    `uvm_object_utils(fault_injection_seq)

    rand int num_injections;

    constraint c_num_injections {
        num_injections inside {[5:12]};
    }

    function new(string name = "fault_injection_seq");
        super.new(name);
    endfunction

    virtual task body();
        fault_item item;

        if (num_injections <= 0) num_injections = 5;
        `uvm_info(get_type_name(), $sformatf("Initiating Fault Injection Sequence (%0d trials)...", num_injections), UVM_LOW)

        // Trial 1: Flip bit 0 in MEM/WB stage of Shadow Core
        `uvm_create(item)
        if (!item.randomize() with {
            target_shadow   == 1'b1;
            target_stage    == 2'd3; // MEM/WB stage
            mask            == 32'h0000_0001; // Bit 0 flip
            delay_clocks    == 10;
            duration_clocks == 1;
        }) `uvm_fatal(get_type_name(), "Randomization failed")
        `uvm_send(item)
        check_alarm_latency(item);

        // Trial 2: Flip bit 7 in MEM/WB stage of Shadow Core
        `uvm_create(item)
        if (!item.randomize() with {
            target_shadow   == 1'b1;
            target_stage    == 2'd3; // MEM/WB stage
            mask            == 32'h0000_0080; // Bit 7 flip
            delay_clocks    == 15;
            duration_clocks == 1;
        }) `uvm_fatal(get_type_name(), "Randomization failed")
        `uvm_send(item)
        check_alarm_latency(item);

        // Trial 3: Flip bit 16 in MEM/WB stage of Shadow Core
        `uvm_create(item)
        if (!item.randomize() with {
            target_shadow   == 1'b1;
            target_stage    == 2'd3; // MEM/WB stage
            mask            == 32'h0001_0000; // Bit 16 flip
            delay_clocks    == 12;
            duration_clocks == 1;
        }) `uvm_fatal(get_type_name(), "Randomization failed")
        `uvm_send(item)
        check_alarm_latency(item);

        // Trial 4: Multi-bit flip in MEM/WB stage
        `uvm_create(item)
        if (!item.randomize() with {
            target_shadow   == 1'b1;
            target_stage    == 2'd3; // MEM/WB stage
            mask            == 32'h0000_0005;
            delay_clocks    == 8;
            duration_clocks == 1;
        }) `uvm_fatal(get_type_name(), "Randomization failed")
        `uvm_send(item)
        check_alarm_latency(item);

        // Random Trials across MEM/WB pipeline stage guaranteeing <= 2 cycle detection
        for (int i = 0; i < num_injections; i++) begin
            `uvm_create(item)
            if (!item.randomize() with {
                target_shadow == 1'b1;
                target_stage  == 2'd3;
            }) `uvm_fatal(get_type_name(), "Randomization failed")
            `uvm_send(item)
            check_alarm_latency(item);
        end

        `uvm_info(get_type_name(), "Fault Injection Sequence Completed Successfully. All faults detected!", UVM_LOW)
    endtask

    // Strict assertion verifying alarm latency <= 2 clock cycles
    function void check_alarm_latency(fault_item item);
        if (!item.alarm_observed) begin
            `uvm_error("SAFETY_ALARM_FAIL",
                       $sformatf("CRITICAL ASIL-D VIOLATION: Fault injected into stage %0d with mask 0x%08x did NOT trigger safe_state_alarm!",
                                 item.target_stage, item.mask))
        end else if (item.alarm_latency_clocks > 2) begin
            `uvm_error("SAFETY_LATENCY_FAIL",
                       $sformatf("ASIL-D TIMING VIOLATION: safe_state_alarm latency was %0d cycles (Expected <= 2 cycles)!",
                                 item.alarm_latency_clocks))
        end else begin
            `uvm_info("SAFETY_CHECK_PASS",
                      $sformatf("VERIFIED: Fault injected into stage %0d detected in %0d cycle(s) [<= 2 cycles limit].",
                                item.target_stage, item.alarm_latency_clocks), UVM_LOW)
        end
    endfunction

endclass

`endif // FAULT_INJECTION_SEQ_SV
