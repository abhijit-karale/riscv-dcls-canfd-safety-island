//=============================================================================
// File: canfd_driver.sv
// Description: UVM Driver for CAN-FD bus.
//              Drives serialized CAN-FD frames onto the physical CAN RX line
//              with appropriate bit timings and delivers ACK responses.
//=============================================================================

`ifndef CANFD_DRIVER_SV
`define CANFD_DRIVER_SV

class canfd_driver extends uvm_driver #(canfd_item);
    `uvm_component_utils(canfd_driver)

    virtual safety_island_if vif;

    // Nominal and Data Bit Time (in clocks or ns)
    int nom_bit_clks  = 80; // 500 kbps @ 40 MHz
    int data_bit_clks = 20; // 2 Mbps @ 40 MHz

    function new(string name = "canfd_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual safety_island_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("DRV_NOVIF", "Could not get virtual safety_island_if from config_db")
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        // Default bus state is recessive (1)
        vif.can_rx <= 1'b1;

        // Wait for reset release
        @(posedge vif.clk_can);
        while (!vif.rst_can_n) @(posedge vif.clk_can);

        forever begin
            seq_item_port.get_next_item(req);
            `uvm_info(get_type_name(), $sformatf("Driving item:\n%s", req.convert2string()), UVM_HIGH)
            drive_frame(req);
            seq_item_port.item_done();
        end
    endtask

    // Helper to send a single bit with specified duration
    task drive_bit(bit b, int clk_count);
        vif.can_rx <= b;
        repeat (clk_count) @(posedge vif.clk_can);
    endtask

    // Serializes CAN-FD frame onto RX line
    virtual task drive_frame(canfd_item item);
        int bit_clks;
        bit_clks = nom_bit_clks;

        // Inter-frame idle delay
        repeat (item.inter_frame_delay * nom_bit_clks) @(posedge vif.clk_can);

        // 1. SOF (Dominant 0)
        drive_bit(1'b0, nom_bit_clks);

        // 2. Identifier (11-bit standard)
        for (int i = 10; i >= 0; i--) begin
            drive_bit(item.id[i], nom_bit_clks);
        end

        // 3. Control Field
        drive_bit(1'b0, nom_bit_clks); // RRS
        drive_bit(1'b0, nom_bit_clks); // IDE (standard)
        drive_bit(item.is_canfd, nom_bit_clks); // FDF
        drive_bit(1'b0, nom_bit_clks); // res
        drive_bit(item.bitrate_switch, nom_bit_clks); // BRS

        // If BRS is active, switch to Fast Data bit rate
        if (item.bitrate_switch) begin
            bit_clks = data_bit_clks;
        end

        drive_bit(item.esi, bit_clks); // ESI

        // DLC (4 bits)
        for (int i = 3; i >= 0; i--) begin
            drive_bit(item.dlc[i], bit_clks);
        end

        // 4. Data Payload
        foreach (item.payload[idx]) begin
            for (int b = 7; b >= 0; b--) begin
                drive_bit(item.payload[idx][b], bit_clks);
            end
        end

        // 5. CRC Field (17 or 21 bits)
        if (item.dlc > 4'd10) begin
            for (int i = 20; i >= 0; i--) drive_bit(item.crc[i], bit_clks);
        end else begin
            for (int i = 16; i >= 0; i--) drive_bit(item.crc[i], bit_clks);
        end

        // CRC Delimiter (Recessive 1) - switch back to Nominal rate
        drive_bit(1'b1, nom_bit_clks);
        bit_clks = nom_bit_clks;

        // 6. ACK Slot (Drive Dominant 0 to acknowledge reception if testing DUT RX)
        drive_bit(1'b0, nom_bit_clks);
        drive_bit(1'b1, nom_bit_clks); // ACK Delimiter

        // 7. EOF (7 recessive bits) + Intermission (3 bits)
        repeat (10) drive_bit(1'b1, nom_bit_clks);
    endtask

endclass

`endif // CANFD_DRIVER_SV
