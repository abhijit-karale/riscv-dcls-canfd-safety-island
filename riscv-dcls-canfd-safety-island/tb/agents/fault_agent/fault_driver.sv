//=============================================================================
// File: fault_driver.sv
// Description: UVM Driver for Hardware Fault Injection Unit.
//              Injects transient SEU faults into the core pipeline and measures
//              the exact clock-cycle detection latency to safe_state_alarm.
//=============================================================================

`ifndef FAULT_DRIVER_SV
`define FAULT_DRIVER_SV

class fault_driver extends uvm_driver #(fault_item);
    `uvm_component_utils(fault_driver)

    virtual safety_island_if vif;
    uvm_analysis_port #(fault_item) fault_ap;

    function new(string name = "fault_driver", uvm_component parent = null);
        super.new(name, parent);
        fault_ap = new("fault_ap", this);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual safety_island_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("FAULT_DRV_NOVIF", "Could not get virtual safety_island_if from config_db")
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        // Default quiescent state
        vif.fiu_en            <= 1'b0;
        vif.fiu_target_shadow <= 1'b1;
        vif.fiu_stage         <= '0;
        vif.fiu_bit_idx       <= '0;
        vif.fiu_mask          <= '0;
        vif.alarm_clear_n     <= 1'b1;

        // Wait for Core reset release
        @(posedge vif.clk_core);
        while (!vif.rst_core_n) @(posedge vif.clk_core);

        forever begin
            seq_item_port.get_next_item(req);
            inject_fault(req);
            fault_ap.write(req);
            seq_item_port.item_done();
        end
    endtask

    virtual task inject_fault(fault_item item);
        int cycle_count;

        // Wait for requested delay
        repeat (item.delay_clocks) @(posedge vif.clk_core);

        `uvm_info(get_type_name(), $sformatf("[FIU INJECT] Injecting fault: Stage=%0d Bit=%0d Mask=0x%08x Shadow=%0b",
                  item.target_stage, item.bit_idx, item.mask, item.target_shadow), UVM_LOW)

        // Assert FIU pulse on rising clock edge
        @(posedge vif.clk_core);
        vif.fiu_en            <= 1'b1;
        vif.fiu_target_shadow <= item.target_shadow;
        vif.fiu_stage         <= item.target_stage;
        vif.fiu_bit_idx       <= item.bit_idx;
        vif.fiu_mask          <= item.mask;

        cycle_count = 0;
        item.alarm_observed = 1'b0;

        // Count latency from injection pulse
        while (cycle_count < 10) begin
            @(posedge vif.clk_core);
            cycle_count++;

            // De-assert injection after 1 clock cycle
            if (cycle_count == 1) begin
                vif.fiu_en   <= 1'b0;
                vif.fiu_mask <= 32'd0;
            end

            if (vif.safe_state_alarm) begin
                item.alarm_observed       = 1'b1;
                item.alarm_latency_clocks = cycle_count;
                item.captured_fault_pc    = vif.fault_pc;
                item.captured_fault_status= vif.fault_status;
                `uvm_info(get_type_name(), $sformatf("[ALARM DETECTED] safe_state_alarm fired in %0d clocks (PC=0x%08x, Status=0x%08x)",
                          cycle_count, item.captured_fault_pc, item.captured_fault_status), UVM_LOW)
                break;
            end
        end

        if (!item.alarm_observed) begin
            `uvm_error(get_type_name(), "[ALARM TIMEOUT] safe_state_alarm did NOT assert within 10 clock cycles of fault injection!")
        end

        // Wait, then synchronously clear alarm
        repeat (5) @(posedge vif.clk_core);
        vif.alarm_clear_n <= 1'b0;
        repeat (2) @(posedge vif.clk_core);
        vif.alarm_clear_n <= 1'b1;
        repeat (5) @(posedge vif.clk_core);
    endtask

endclass

`endif // FAULT_DRIVER_SV
