//=============================================================================
// File: fault_item.sv
// Description: UVM Sequence Item for Hardware Fault Injection Unit (FIU).
//              Models Single Event Upsets (SEUs), transient bit flips,
//              and pipeline stage corruptions.
//=============================================================================

`ifndef FAULT_ITEM_SV
`define FAULT_ITEM_SV

class fault_item extends uvm_sequence_item;
    `uvm_object_utils(fault_item)

    // Configuration
    rand bit        target_shadow;     // 1: Shadow Core, 0: Master Core
    rand bit [1:0]  target_stage;      // 0: ID/EX, 1: EX/MEM, 2: MEM/WB, 3: RegFile
    rand bit [4:0]  bit_idx;           // Bit index or RegFile destination
    rand bit [31:0] mask;              // Bit-flip XOR mask
    rand int        delay_clocks;      // Clocks to wait before injection
    rand int        duration_clocks;   // Pulse duration in clocks

    // Results / Verification telemetry
    bit             alarm_observed;
    int             alarm_latency_clocks;
    bit [31:0]      captured_fault_pc;
    bit [31:0]      captured_fault_status;

    // Constraints
    constraint c_fault_mask {
        mask != 32'd0;
        $countones(mask) inside {[1:4]};
    }

    constraint c_timing {
        delay_clocks inside {[5:30]};
        duration_clocks inside {[1:2]};
    }

    constraint c_target_default {
        target_shadow == 1'b1; // Default to shadow core for safety island testing
    }

    function new(string name = "fault_item");
        super.new(name);
    endfunction

    virtual function string convert2string();
        return $sformatf("Fault Item: Target=%s Stage=%0d Bit=%0d Mask=0x%08x Delay=%0d Duration=%0d | Latency=%0d Clks Alarm=%0b",
                         target_shadow ? "SHADOW" : "MASTER", target_stage, bit_idx, mask, delay_clocks, duration_clocks,
                         alarm_latency_clocks, alarm_observed);
    endfunction

    virtual function void do_copy(uvm_object rhs);
        fault_item rhs_;
        if (!$cast(rhs_, rhs)) `uvm_fatal("FAULT_ITEM_CAST", "Cast failed")
        super.do_copy(rhs);
        this.target_shadow       = rhs_.target_shadow;
        this.target_stage        = rhs_.target_stage;
        this.bit_idx             = rhs_.bit_idx;
        this.mask                = rhs_.mask;
        this.delay_clocks        = rhs_.delay_clocks;
        this.duration_clocks     = rhs_.duration_clocks;
        this.alarm_observed      = rhs_.alarm_observed;
        this.alarm_latency_clocks= rhs_.alarm_latency_clocks;
        this.captured_fault_pc   = rhs_.captured_fault_pc;
        this.captured_fault_status= rhs_.captured_fault_status;
    endfunction

endclass

`endif // FAULT_ITEM_SV
