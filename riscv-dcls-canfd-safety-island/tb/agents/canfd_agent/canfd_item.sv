//=============================================================================
// File: canfd_item.sv
// Description: UVM Sequence Item modeling standard and CAN-FD frames.
//              Supports payloads from 0 to 64 bytes, Bit Rate Switch (BRS),
//              extended IDs, and automatic byte length constraints.
//=============================================================================

`ifndef CANFD_ITEM_SV
`define CANFD_ITEM_SV

class canfd_item extends uvm_sequence_item;
    `uvm_object_utils(canfd_item)

    // Frame Fields
    rand bit [28:0] id;
    rand bit        is_extended;     // 0: 11-bit standard ID, 1: 29-bit extended ID
    rand bit        is_canfd;        // 1: CAN FD (FDF=1), 0: Classic CAN
    rand bit        bitrate_switch;  // 1: Fast data rate enabled (BRS=1)
    rand bit        esi;             // Error State Indicator
    rand bit [3:0]  dlc;             // 0..15
    rand bit [7:0]  payload [];      // Payload bytes (0 to 64)
    bit [20:0]      crc;
    bit             crc_error;
    rand int        inter_frame_delay;

    // Length conversion helper
    static function int dlc_to_length(bit [3:0] dlc_val);
        case (dlc_val)
            4'd0:  return 0;
            4'd1:  return 1;
            4'd2:  return 2;
            4'd3:  return 3;
            4'd4:  return 4;
            4'd5:  return 5;
            4'd6:  return 6;
            4'd7:  return 7;
            4'd8:  return 8;
            4'd9:  return 12;
            4'd10: return 16;
            4'd11: return 20;
            4'd12: return 24;
            4'd13: return 32;
            4'd14: return 48;
            4'd15: return 64;
            default: return 0;
        endcase
    endfunction

    // Constraints
    constraint c_dlc {
        dlc inside {[4'd0 : 4'd15]};
    }

    constraint c_payload_size {
        payload.size() == (
            (dlc <= 4'd8)  ? int'(dlc) :
            (dlc == 4'd9)  ? 12 :
            (dlc == 4'd10) ? 16 :
            (dlc == 4'd11) ? 20 :
            (dlc == 4'd12) ? 24 :
            (dlc == 4'd13) ? 32 :
            (dlc == 4'd14) ? 48 : 64
        );
    }

    constraint c_standard_id {
        solve is_extended before id;
        (!is_extended) -> (id <= 29'h7FF);
    }

    constraint c_fd_defaults {
        soft is_canfd == 1'b1;
        inter_frame_delay inside {[2:10]};
    }

    // Constructor
    function new(string name = "canfd_item");
        super.new(name);
    endfunction

    // Custom string representation
    virtual function string convert2string();
        string s;
        s = $sformatf("CAN-FD Frame: ID=0x%0x Ext=%0b FD=%0b BRS=%0b DLC=%0d (Bytes=%0d) Delay=%0d\n  Payload: [",
                      id, is_extended, is_canfd, bitrate_switch, dlc, payload.size(), inter_frame_delay);
        foreach (payload[i]) begin
            s = $sformatf("%s 0x%02x", s, payload[i]);
        end
        s = {s, " ]"};
        return s;
    endfunction

    // Deep copy
    virtual function void do_copy(uvm_object rhs);
        canfd_item rhs_;
        if (!$cast(rhs_, rhs)) begin
            `uvm_fatal("CANFD_ITEM_CAST", "Cast failed in do_copy")
        end
        super.do_copy(rhs);
        this.id                = rhs_.id;
        this.is_extended       = rhs_.is_extended;
        this.is_canfd          = rhs_.is_canfd;
        this.bitrate_switch    = rhs_.bitrate_switch;
        this.esi               = rhs_.esi;
        this.dlc               = rhs_.dlc;
        this.payload           = new[rhs_.payload.size()](rhs_.payload);
        this.crc               = rhs_.crc;
        this.crc_error         = rhs_.crc_error;
        this.inter_frame_delay = rhs_.inter_frame_delay;
    endfunction

    // Comparison
    virtual function bit do_compare(uvm_object rhs, uvm_comparer comparer);
        canfd_item rhs_;
        if (!$cast(rhs_, rhs)) return 0;
        if (!super.do_compare(rhs, comparer)) return 0;
        if (id != rhs_.id) return 0;
        if (is_extended != rhs_.is_extended) return 0;
        if (dlc != rhs_.dlc) return 0;
        if (payload.size() != rhs_.payload.size()) return 0;
        foreach (payload[i]) begin
            if (payload[i] != rhs_.payload[i]) return 0;
        end
        return 1;
    endfunction

endclass

`endif // CANFD_ITEM_SV
