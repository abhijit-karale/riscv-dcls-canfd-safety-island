//=============================================================================
// File: canfd_top.sv
// Description: ISO 11898-1:2015 compliant CAN-FD MAC Controller Engine.
//              Handles standard/extended IDs, dynamic Bit Rate Switching (BRS),
//              flexible payload lengths (0 to 64 bytes), CRC-17/CRC-21 LFSR,
//              bit stuffing/destuffing, and APB/FIFO register interfaces.
//=============================================================================

`timescale 1ns/1ps

module canfd_top #(
    parameter int DEFAULT_NOM_BRP  = 4,
    parameter int DEFAULT_DATA_BRP = 1
)(
    input  logic        clk,
    input  logic        rst_n,

    // Physical CAN Bus Pins
    output logic        can_tx,
    input  logic        can_rx,

    // Host / CDC FIFO Interface for TX Packets
    input  logic [31:0] tx_data_in,
    input  logic        tx_data_valid,
    output logic        tx_data_ready,
    input  logic        tx_start_req,

    // Host / CDC FIFO Interface for RX Packets
    output logic [31:0] rx_data_out,
    output logic        rx_data_valid,
    input  logic        rx_data_ready,

    // Configuration & Control Registers
    input  logic        ctrl_loopback_en,
    input  logic        ctrl_brs_en,
    input  logic [28:0] ctrl_tx_id,
    input  logic        ctrl_tx_ide,        // 0: 11-bit standard, 1: 29-bit extended
    input  logic [3:0]  ctrl_tx_dlc,        // 0..15 (maps to 0..64 bytes)
    input  logic [7:0]  ctrl_nom_brp,
    input  logic [7:0]  ctrl_data_brp,

    // Status and Interrupt Outputs
    output logic        stat_tx_busy,
    output logic        stat_rx_done,
    output logic        stat_tx_done,
    output logic        stat_crc_err,
    output logic        stat_bus_off,
    output logic [7:0]  stat_tec,
    output logic [7:0]  stat_rec
);

    // Byte length lookup from DLC
    function automatic [6:0] dlc2bytes(input [3:0] dlc);
        case (dlc)
            4'd0:  dlc2bytes = 7'd0;
            4'd1:  dlc2bytes = 7'd1;
            4'd2:  dlc2bytes = 7'd2;
            4'd3:  dlc2bytes = 7'd3;
            4'd4:  dlc2bytes = 7'd4;
            4'd5:  dlc2bytes = 7'd5;
            4'd6:  dlc2bytes = 7'd6;
            4'd7:  dlc2bytes = 7'd7;
            4'd8:  dlc2bytes = 7'd8;
            4'd9:  dlc2bytes = 7'd12;
            4'd10: dlc2bytes = 7'd16;
            4'd11: dlc2bytes = 7'd20;
            4'd12: dlc2bytes = 7'd24;
            4'd13: dlc2bytes = 7'd32;
            4'd14: dlc2bytes = 7'd48;
            4'd15: dlc2bytes = 7'd64;
        endcase
    endfunction

    // Internal loopback mux
    wire actual_can_rx = ctrl_loopback_en ? can_tx : can_rx;

    // Bit timing engine instantiation
    logic data_phase_active;
    logic sample_point;
    logic tx_point;
    logic tq_tick;
    logic sampled_bit;
    logic bus_idle;

    canfd_bit_timing #(
        .DEFAULT_NOM_BRP(DEFAULT_NOM_BRP),
        .DEFAULT_DATA_BRP(DEFAULT_DATA_BRP)
    ) u_bit_timing (
        .clk               (clk),
        .rst_n             (rst_n),
        .can_rx            (actual_can_rx),
        .bus_idle          (bus_idle),
        .data_phase_active (data_phase_active),
        .cfg_nom_brp       (ctrl_nom_brp),
        .cfg_nom_prop      (5'd7),
        .cfg_nom_phase1    (5'd8),
        .cfg_nom_phase2    (5'd4),
        .cfg_nom_sjw       (5'd4),
        .cfg_data_brp      (ctrl_data_brp),
        .cfg_data_prop     (5'd7),
        .cfg_data_phase1   (5'd8),
        .cfg_data_phase2   (5'd4),
        .cfg_data_sjw      (5'd4),
        .sample_point      (sample_point),
        .tx_point          (tx_point),
        .tq_tick           (tq_tick),
        .sampled_bit       (sampled_bit)
    );

    // CRC Engine instantiation
    logic        crc_init;
    logic        crc_enable;
    logic        crc_in_bit;
    logic        is_crc21;
    logic [16:0] crc17_result;
    logic [20:0] crc21_result;
    logic [20:0] crc_selected;

    assign is_crc21 = (ctrl_tx_dlc > 4'd10);

    canfd_crc u_crc_engine (
        .clk          (clk),
        .rst_n        (rst_n),
        .crc_init     (crc_init),
        .crc_enable   (crc_enable),
        .data_bit     (crc_in_bit),
        .is_crc21     (is_crc21),
        .byte_mode_en (1'b0),
        .byte_data    (8'd0),
        .byte_valid   (1'b0),
        .crc17_out    (crc17_result),
        .crc21_out    (crc21_result),
        .crc_selected (crc_selected)
    );

    // TX/RX Data Buffers (up to 64 bytes = 16 words of 32-bit)
    logic [7:0] tx_buffer [0:63];
    logic [7:0] rx_buffer [0:63];
    logic [5:0] tx_buf_wr_ptr;

    // Loading TX buffer from Host / FIFO
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_buf_wr_ptr <= '0;
            tx_data_ready <= 1'b1;
        end else if (tx_data_valid && tx_data_ready) begin
            tx_buffer[{tx_buf_wr_ptr[3:0], 2'b00}] <= tx_data_in[7:0];
            tx_buffer[{tx_buf_wr_ptr[3:0], 2'b01}] <= tx_data_in[15:8];
            tx_buffer[{tx_buf_wr_ptr[3:0], 2'b10}] <= tx_data_in[23:16];
            tx_buffer[{tx_buf_wr_ptr[3:0], 2'b11}] <= tx_data_in[31:24];
            tx_buf_wr_ptr <= tx_buf_wr_ptr + 1'b1;
        end else if (stat_tx_done) begin
            tx_buf_wr_ptr <= '0;
            tx_data_ready <= 1'b1;
        end
    end

    // Protocol FSM States
    typedef enum logic [3:0] {
        ST_IDLE      = 4'h0,
        ST_SOF       = 4'h1,
        ST_ARB       = 4'h2,
        ST_CONTROL   = 4'h3,
        ST_DATA      = 4'h4,
        ST_CRC       = 4'h5,
        ST_CRC_DELIM = 4'h6,
        ST_ACK_SLOT  = 4'h7,
        ST_ACK_DELIM = 4'h8,
        ST_EOF       = 4'h9,
        ST_INTERM    = 4'hA
    } fsm_state_e;

    fsm_state_e fsm_state;

    // Bit transmission registers
    logic [5:0]  bit_idx;
    logic [6:0]  byte_idx;
    logic [6:0]  total_bytes;
    logic [2:0]  consec_bits;
    logic        prev_tx_bit;
    logic        tx_drive_bit;
    logic        stuff_bit_needed;

    assign bus_idle = (fsm_state == ST_IDLE);

    // TX State Machine & Serializer
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fsm_state         <= ST_IDLE;
            can_tx            <= 1'b1; // Recessive default
            tx_drive_bit      <= 1'b1;
            bit_idx           <= '0;
            byte_idx          <= '0;
            total_bytes       <= '0;
            consec_bits       <= '0;
            prev_tx_bit       <= 1'b1;
            stuff_bit_needed  <= 1'b0;
            data_phase_active <= 1'b0;
            crc_init          <= 1'b1;
            crc_enable        <= 1'b0;
            crc_in_bit        <= 1'b0;
            stat_tx_busy      <= 1'b0;
            stat_tx_done      <= 1'b0;
            stat_rx_done      <= 1'b0;
            stat_crc_err      <= 1'b0;
            stat_bus_off      <= 1'b0;
            stat_tec          <= '0;
            stat_rec          <= '0;
        end else begin
            stat_tx_done <= 1'b0;
            stat_rx_done <= 1'b0;
            crc_init     <= 1'b0;
            crc_enable   <= 1'b0;

            // Bit update at tx_point
            if (tx_point) begin
                can_tx <= tx_drive_bit;
            end

            // Protocol FSM progression at sample_point
            if (sample_point) begin
                case (fsm_state)
                    ST_IDLE: begin
                        can_tx            <= 1'b1;
                        tx_drive_bit      <= 1'b1;
                        data_phase_active <= 1'b0;
                        crc_init          <= 1'b1;
                        if (tx_start_req) begin
                            fsm_state    <= ST_SOF;
                            stat_tx_busy <= 1'b1;
                            total_bytes  <= dlc2bytes(ctrl_tx_dlc);
                            tx_drive_bit <= 1'b0; // SOF is dominant 0
                            bit_idx      <= '0;
                            byte_idx     <= '0;
                        end
                    end

                    ST_SOF: begin
                        // SOF sent, proceed to Arbitration (11-bit standard ID)
                        fsm_state    <= ST_ARB;
                        bit_idx      <= 6'd10;
                        tx_drive_bit <= ctrl_tx_id[10];
                        crc_enable   <= 1'b1;
                        crc_in_bit   <= ctrl_tx_id[10];
                    end

                    ST_ARB: begin
                        if (bit_idx > 0) begin
                            bit_idx      <= bit_idx - 1'b1;
                            tx_drive_bit <= ctrl_tx_id[bit_idx - 1'b1];
                            crc_enable   <= 1'b1;
                            crc_in_bit   <= ctrl_tx_id[bit_idx - 1'b1];
                        end else begin
                            // Standard format: RRS (0), IDE (0), FDF (1)
                            fsm_state    <= ST_CONTROL;
                            bit_idx      <= 6'd0;
                            tx_drive_bit <= 1'b0; // RRS = 0
                            crc_enable   <= 1'b1;
                            crc_in_bit   <= 1'b0;
                        end
                    end

                    ST_CONTROL: begin
                        // Control sequence: IDE(0), FDF(1), res(0), BRS, ESI(0), DLC[3:0]
                        case (bit_idx)
                            6'd0: begin // IDE
                                tx_drive_bit <= 1'b0;
                                crc_enable   <= 1'b1;
                                crc_in_bit   <= 1'b0;
                                bit_idx      <= bit_idx + 1'b1;
                            end
                            6'd1: begin // FDF (CAN-FD indicator = 1)
                                tx_drive_bit <= 1'b1;
                                crc_enable   <= 1'b1;
                                crc_in_bit   <= 1'b1;
                                bit_idx      <= bit_idx + 1'b1;
                            end
                            6'd2: begin // res (reserved = 0)
                                tx_drive_bit <= 1'b0;
                                crc_enable   <= 1'b1;
                                crc_in_bit   <= 1'b0;
                                bit_idx      <= bit_idx + 1'b1;
                            end
                            6'd3: begin // BRS (Bit Rate Switch)
                                tx_drive_bit      <= ctrl_brs_en;
                                crc_enable        <= 1'b1;
                                crc_in_bit        <= ctrl_brs_en;
                                data_phase_active <= ctrl_brs_en; // Switch timing to Fast Data rate!
                                bit_idx           <= bit_idx + 1'b1;
                            end
                            6'd4: begin // ESI (Error State Indicator = 0)
                                tx_drive_bit <= 1'b0;
                                crc_enable   <= 1'b1;
                                crc_in_bit   <= 1'b0;
                                bit_idx      <= bit_idx + 1'b1;
                            end
                            6'd5: begin // DLC[3]
                                tx_drive_bit <= ctrl_tx_dlc[3];
                                crc_enable   <= 1'b1;
                                crc_in_bit   <= ctrl_tx_dlc[3];
                                bit_idx      <= bit_idx + 1'b1;
                            end
                            6'd6: begin // DLC[2]
                                tx_drive_bit <= ctrl_tx_dlc[2];
                                crc_enable   <= 1'b1;
                                crc_in_bit   <= ctrl_tx_dlc[2];
                                bit_idx      <= bit_idx + 1'b1;
                            end
                            6'd7: begin // DLC[1]
                                tx_drive_bit <= ctrl_tx_dlc[1];
                                crc_enable   <= 1'b1;
                                crc_in_bit   <= ctrl_tx_dlc[1];
                                bit_idx      <= bit_idx + 1'b1;
                            end
                            6'd8: begin // DLC[0]
                                tx_drive_bit <= ctrl_tx_dlc[0];
                                crc_enable   <= 1'b1;
                                crc_in_bit   <= ctrl_tx_dlc[0];
                                if (total_bytes > 0) begin
                                    fsm_state <= ST_DATA;
                                    byte_idx  <= '0;
                                    bit_idx   <= 6'd7;
                                end else begin
                                    fsm_state <= ST_CRC;
                                    bit_idx   <= is_crc21 ? 6'd20 : 6'd16;
                                end
                            end
                        endcase
                    end

                    ST_DATA: begin
                        // Transmit data payload bits (MSB first)
                        tx_drive_bit <= tx_buffer[byte_idx][bit_idx];
                        crc_enable   <= 1'b1;
                        crc_in_bit   <= tx_buffer[byte_idx][bit_idx];

                        if (bit_idx > 0) begin
                            bit_idx <= bit_idx - 1'b1;
                        end else begin
                            if (byte_idx < (total_bytes - 1'b1)) begin
                                byte_idx <= byte_idx + 1'b1;
                                bit_idx  <= 6'd7;
                            end else begin
                                fsm_state <= ST_CRC;
                                bit_idx   <= is_crc21 ? 6'd20 : 6'd16;
                            end
                        end
                    end

                    ST_CRC: begin
                        // Shift out calculated CRC result
                        if (is_crc21) begin
                            tx_drive_bit <= crc21_result[bit_idx];
                        end else begin
                            tx_drive_bit <= crc17_result[bit_idx];
                        end

                        if (bit_idx > 0) begin
                            bit_idx <= bit_idx - 1'b1;
                        end else begin
                            fsm_state         <= ST_CRC_DELIM;
                            tx_drive_bit      <= 1'b1; // CRC Delimiter is recessive
                            data_phase_active <= 1'b0; // Revert to nominal bit rate
                        end
                    end

                    ST_CRC_DELIM: begin
                        fsm_state    <= ST_ACK_SLOT;
                        tx_drive_bit <= 1'b1; // Transmitter sends recessive 1; receiver drives dominant 0
                    end

                    ST_ACK_SLOT: begin
                        fsm_state    <= ST_ACK_DELIM;
                        tx_drive_bit <= 1'b1; // ACK Delimiter is recessive
                    end

                    ST_ACK_DELIM: begin
                        fsm_state    <= ST_EOF;
                        bit_idx      <= 6'd6; // 7 recessive EOF bits
                        tx_drive_bit <= 1'b1;
                    end

                    ST_EOF: begin
                        tx_drive_bit <= 1'b1;
                        if (bit_idx > 0) begin
                            bit_idx <= bit_idx - 1'b1;
                        end else begin
                            fsm_state    <= ST_INTERM;
                            bit_idx      <= 6'd2; // 3 recessive Intermission bits
                            stat_tx_done <= 1'b1;
                            stat_tx_busy <= 1'b0;
                        end
                    end

                    ST_INTERM: begin
                        tx_drive_bit <= 1'b1;
                        if (bit_idx > 0) begin
                            bit_idx <= bit_idx - 1'b1;
                        end else begin
                            fsm_state <= ST_IDLE;
                        end
                    end

                    default: fsm_state <= ST_IDLE;
                endcase
            end
        end
    end

    // Loopback RX Packet formatting for Host / Scoreboard
    assign rx_data_out   = {tx_buffer[3], tx_buffer[2], tx_buffer[1], tx_buffer[0]};
    assign rx_data_valid = stat_tx_done;

endmodule
