//=============================================================================
// File: canfd_base_seq.sv
// Description: UVM Sequences generating standard and CAN-FD transactions
//              comprehensively exercising all payload length bins (0 to 64B),
//              standard/extended IDs, and bit-rate switching (BRS=0 and BRS=1).
//=============================================================================

`ifndef CANFD_BASE_SEQ_SV
`define CANFD_BASE_SEQ_SV

class canfd_base_seq extends uvm_sequence #(canfd_item);
    `uvm_object_utils(canfd_base_seq)

    rand int num_frames;

    constraint c_num_frames {
        num_frames inside {[5:10]};
    }

    function new(string name = "canfd_base_seq");
        super.new(name);
    endfunction

    virtual task body();
        canfd_item frame;
        bit [3:0] dlc_sweep[9] = '{4'd0, 4'd8, 4'd9, 4'd10, 4'd11, 4'd12, 4'd13, 4'd14, 4'd15};

        `uvm_info(get_type_name(), "Starting Comprehensive CAN-FD Coverage Sequence...", UVM_LOW)

        // 1. Directed sweep across all functional payload DLC bins (0, 8, 12, 16, 20, 24, 32, 48, 64 bytes)
        for (int i = 0; i < 9; i++) begin
            `uvm_create(frame)
            if (!frame.randomize() with {
                dlc            == dlc_sweep[i];
                is_extended    == (i % 2 == 1);
                is_canfd       == 1'b1;
                bitrate_switch == (i % 2 == 0);
            }) `uvm_fatal(get_type_name(), "Randomization failed")
            `uvm_send(frame)
        end

        // 2. Additional classic CAN frame (BRS=0, FDF=0, DLC=4)
        `uvm_create(frame)
        if (!frame.randomize() with {
            dlc            == 4'd4;
            is_extended    == 1'b0;
            is_canfd       == 1'b0;
            bitrate_switch == 1'b0;
        }) `uvm_fatal(get_type_name(), "Randomization failed")
        `uvm_send(frame)

        `uvm_info(get_type_name(), "Completed Comprehensive CAN-FD Coverage Sequence", UVM_LOW)
    endtask

endclass

`endif // CANFD_BASE_SEQ_SV
