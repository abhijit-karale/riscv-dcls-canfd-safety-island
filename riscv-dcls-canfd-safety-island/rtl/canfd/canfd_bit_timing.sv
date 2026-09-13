//=============================================================================
// File: canfd_bit_timing.sv
// Description: Dual-rate Bit Timing Engine for CAN-FD supporting Nominal
//              (Arbitration) and Fast Data (Payload) phases with dynamic
//              hard sync, resynchronization (SJW), and sample point generation.
// Standard: ISO 11898-1:2015
//=============================================================================

`timescale 1ns/1ps

module canfd_bit_timing #(
    // Default 40 MHz clock config:
    // Nominal: 500 kbps -> 80 clks/bit. BRP=4 (TQ=100ns), Total=20 TQ.
    // Prop=7, Phase1=8, Phase2=4, SJW=4 (Sample point @ 80%)
    // Data: 2 Mbps -> 20 clks/bit. BRP=1 (TQ=25ns), Total=20 TQ.
    // Prop=7, Phase1=8, Phase2=4, SJW=4 (Sample point @ 80%)
    parameter int DEFAULT_NOM_BRP    = 4,
    parameter int DEFAULT_NOM_PROP   = 7,
    parameter int DEFAULT_NOM_PHASE1 = 8,
    parameter int DEFAULT_NOM_PHASE2 = 4,
    parameter int DEFAULT_NOM_SJW    = 4,

    parameter int DEFAULT_DATA_BRP    = 1,
    parameter int DEFAULT_DATA_PROP   = 7,
    parameter int DEFAULT_DATA_PHASE1 = 8,
    parameter int DEFAULT_DATA_PHASE2 = 4,
    parameter int DEFAULT_DATA_SJW    = 4
)(
    input  logic        clk,
    input  logic        rst_n,

    // Bus RX pin for edge detection & synchronization
    input  logic        can_rx,
    input  logic        bus_idle,

    // Bit rate selection
    input  logic        data_phase_active, // 0: Nominal timing, 1: Data timing

    // Configuration registers
    input  logic [7:0]  cfg_nom_brp,
    input  logic [4:0]  cfg_nom_prop,
    input  logic [4:0]  cfg_nom_phase1,
    input  logic [4:0]  cfg_nom_phase2,
    input  logic [4:0]  cfg_nom_sjw,

    input  logic [7:0]  cfg_data_brp,
    input  logic [4:0]  cfg_data_prop,
    input  logic [4:0]  cfg_data_phase1,
    input  logic [4:0]  cfg_data_phase2,
    input  logic [4:0]  cfg_data_sjw,

    // Timing event strobes
    output logic        sample_point,      // Pulse to sample received bit
    output logic        tx_point,          // Pulse to transition transmit bit
    output logic        tq_tick,           // Time quantum tick
    output logic        sampled_bit        // Clean filtered/sampled RX bit
);

    // Active timing parameters
    logic [7:0] active_brp;
    logic [4:0] active_prop;
    logic [4:0] active_phase1;
    logic [4:0] active_phase2;
    logic [4:0] active_sjw;

    always_comb begin
        if (data_phase_active) begin
            active_brp    = (cfg_data_brp    != 8'd0) ? cfg_data_brp    : DEFAULT_DATA_BRP[7:0];
            active_prop   = (cfg_data_prop   != 5'd0) ? cfg_data_prop   : DEFAULT_DATA_PROP[4:0];
            active_phase1 = (cfg_data_phase1 != 5'd0) ? cfg_data_phase1 : DEFAULT_DATA_PHASE1[4:0];
            active_phase2 = (cfg_data_phase2 != 5'd0) ? cfg_data_phase2 : DEFAULT_DATA_PHASE2[4:0];
            active_sjw    = (cfg_data_sjw    != 5'd0) ? cfg_data_sjw    : DEFAULT_DATA_SJW[4:0];
        end else begin
            active_brp    = (cfg_nom_brp     != 8'd0) ? cfg_nom_brp     : DEFAULT_NOM_BRP[7:0];
            active_prop   = (cfg_nom_prop    != 5'd0) ? cfg_nom_prop    : DEFAULT_NOM_PROP[4:0];
            active_phase1 = (cfg_nom_phase1  != 5'd0) ? cfg_nom_phase1  : DEFAULT_NOM_PHASE1[4:0];
            active_phase2 = (cfg_nom_phase2  != 5'd0) ? cfg_nom_phase2  : DEFAULT_NOM_PHASE2[4:0];
            active_sjw    = (cfg_nom_sjw     != 5'd0) ? cfg_nom_sjw     : DEFAULT_NOM_SJW[4:0];
        end
    end

    // Input deglitch and edge detection (3-flop synchronizer)
    logic rx_sync0, rx_sync1, rx_sync2;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_sync0 <= 1'b1;
            rx_sync1 <= 1'b1;
            rx_sync2 <= 1'b1;
        end else begin
            rx_sync0 <= can_rx;
            rx_sync1 <= rx_sync0;
            rx_sync2 <= rx_sync1;
        end
    end

    wire rx_recessive_to_dominant = (rx_sync2 == 1'b1) && (rx_sync1 == 1'b0);

    // Baud Rate Prescaler (Time Quantum generator)
    logic [7:0] brp_count;
    logic       tq_pulse;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            brp_count <= '0;
            tq_pulse  <= 1'b0;
        end else begin
            if (brp_count >= (active_brp - 1'b1)) begin
                brp_count <= '0;
                tq_pulse  <= 1'b1;
            end else begin
                brp_count <= brp_count + 1'b1;
                tq_pulse  <= 1'b0;
            end
        end
    end

    assign tq_tick = tq_pulse;

    // Segment State Machine
    typedef enum logic [1:0] {
        SEG_SYNC   = 2'b00,
        SEG_PROP   = 2'b01,
        SEG_PHASE1 = 2'b10,
        SEG_PHASE2 = 2'b11
    } seg_state_e;

    seg_state_e seg_state;
    logic [5:0] tq_count_in_seg;
    logic [4:0] phase1_adjusted;
    logic [4:0] phase2_adjusted;

    // Resynchronization Jump Width compensation
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            seg_state        <= SEG_SYNC;
            tq_count_in_seg  <= '0;
            sample_point     <= 1'b0;
            tx_point         <= 1'b0;
            phase1_adjusted  <= active_phase1;
            phase2_adjusted  <= active_phase2;
            sampled_bit      <= 1'b1;
        end else begin
            sample_point <= 1'b0;
            tx_point     <= 1'b0;

            // Hard sync on bus idle or recessive-to-dominant edge outside of sync
            if (rx_recessive_to_dominant && bus_idle) begin
                seg_state        <= SEG_PROP;
                tq_count_in_seg  <= '0;
                phase1_adjusted  <= active_phase1;
                phase2_adjusted  <= active_phase2;
            end else if (tq_pulse) begin
                case (seg_state)
                    SEG_SYNC: begin
                        tx_point        <= 1'b1;
                        seg_state       <= SEG_PROP;
                        tq_count_in_seg <= '0;
                    end

                    SEG_PROP: begin
                        if (tq_count_in_seg >= (active_prop - 1'b1)) begin
                            seg_state       <= SEG_PHASE1;
                            tq_count_in_seg <= '0;
                        end else begin
                            tq_count_in_seg <= tq_count_in_seg + 1'b1;
                        end
                    end

                    SEG_PHASE1: begin
                        if (tq_count_in_seg >= (phase1_adjusted - 1'b1)) begin
                            seg_state       <= SEG_PHASE2;
                            tq_count_in_seg <= '0;
                            sample_point    <= 1'b1;
                            sampled_bit     <= rx_sync1;
                        end else begin
                            tq_count_in_seg <= tq_count_in_seg + 1'b1;
                        end
                    end

                    SEG_PHASE2: begin
                        if (tq_count_in_seg >= (phase2_adjusted - 1'b1)) begin
                            seg_state        <= SEG_SYNC;
                            tq_count_in_seg  <= '0;
                            phase1_adjusted  <= active_phase1;
                            phase2_adjusted  <= active_phase2;
                        end else begin
                            tq_count_in_seg  <= tq_count_in_seg + 1'b1;
                        end
                    end
                endcase
            end
        end
    end

endmodule
