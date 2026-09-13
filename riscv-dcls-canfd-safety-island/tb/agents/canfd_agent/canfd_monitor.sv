//=============================================================================
// File: canfd_monitor.sv
// Description: UVM Monitor for CAN-FD bus.
//              Observes CAN bus transitions, samples serialized bits at nominal
//              and data sample points using cycle-accurate bit tracking,
//              decodes frames, and publishes to Scoreboard.
//=============================================================================

`ifndef CANFD_MONITOR_SV
`define CANFD_MONITOR_SV

class canfd_monitor extends uvm_monitor;
    `uvm_component_utils(canfd_monitor)

    virtual safety_island_if vif;
    uvm_analysis_port #(canfd_item) item_collected_port;

    int nom_bit_clks  = 80;
    int data_bit_clks = 20;

    function new(string name = "canfd_monitor", uvm_component parent = null);
        super.new(name, parent);
        item_collected_port = new("item_collected_port", this);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual safety_island_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("MON_NOVIF", "Could not get virtual safety_island_if from config_db")
        end
    endfunction

    // Helper task to sample a bit exactly at mid-point and finish the bit window
    task sample_bit(input int duration_clks, output bit b);
        repeat (duration_clks / 2) @(posedge vif.clk_can);
        b = vif.can_rx;
        repeat (duration_clks - (duration_clks / 2)) @(posedge vif.clk_can);
    endtask

    virtual task run_phase(uvm_phase phase);
        canfd_item frame;
        bit dummy;

        // Wait for reset release
        @(posedge vif.clk_can);
        while (!vif.rst_can_n) @(posedge vif.clk_can);

        forever begin
            // Detect SOF (recessive to dominant edge on can_rx)
            @(negedge vif.can_rx);

            frame = canfd_item::type_id::create("monitored_frame");

            // 1. SOF
            sample_bit(nom_bit_clks, dummy);

            // 2. 11-bit Identifier
            for (int i = 10; i >= 0; i--) begin
                sample_bit(nom_bit_clks, frame.id[i]);
            end

            // 3. Control bits: RRS, IDE, FDF, res, BRS
            sample_bit(nom_bit_clks, dummy); // RRS
            sample_bit(nom_bit_clks, frame.is_extended);
            sample_bit(nom_bit_clks, frame.is_canfd);
            sample_bit(nom_bit_clks, dummy); // res
            sample_bit(nom_bit_clks, frame.bitrate_switch);

            // 4. Data phase timing determination
            begin
                int cur_bit_clks;
                int byte_len;
                cur_bit_clks = frame.bitrate_switch ? data_bit_clks : nom_bit_clks;

                // ESI
                sample_bit(cur_bit_clks, frame.esi);

                // DLC (4 bits)
                for (int i = 3; i >= 0; i--) begin
                    sample_bit(cur_bit_clks, frame.dlc[i]);
                end

                byte_len = canfd_item::dlc_to_length(frame.dlc);
                frame.payload = new[byte_len];

                // Data Payload
                for (int byte_idx = 0; byte_idx < byte_len; byte_idx++) begin
                    for (int b = 7; b >= 0; b--) begin
                        sample_bit(cur_bit_clks, frame.payload[byte_idx][b]);
                    end
                end

                // CRC
                if (frame.dlc > 4'd10) begin
                    for (int i = 20; i >= 0; i--) begin
                        sample_bit(cur_bit_clks, frame.crc[i]);
                    end
                end else begin
                    for (int i = 16; i >= 0; i--) begin
                        sample_bit(cur_bit_clks, frame.crc[i]);
                    end
                end

                // Revert to nominal rate for Delimiters, ACK, EOF
                sample_bit(nom_bit_clks, dummy); // CRC Delimiter
                sample_bit(nom_bit_clks, dummy); // ACK Slot
                sample_bit(nom_bit_clks, dummy); // ACK Delimiter
                repeat (7) sample_bit(nom_bit_clks, dummy); // EOF
            end

            `uvm_info(get_type_name(), $sformatf("Monitored Frame:\n%s", frame.convert2string()), UVM_MEDIUM)
            item_collected_port.write(frame);
        end
    endtask

endclass

`endif // CANFD_MONITOR_SV
