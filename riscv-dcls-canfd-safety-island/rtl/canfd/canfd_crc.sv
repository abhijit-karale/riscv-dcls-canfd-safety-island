//=============================================================================
// File: canfd_crc.sv
// Description: ISO 11898-1:2015 CAN-FD Hardware CRC-17 and CRC-21 LFSR Engines.
//              - CRC-17: Payloads <= 16 bytes (Poly: 0x1685B, Init: 0x10000)
//              - CRC-21: Payloads > 16 bytes (Poly: 0x102899, Init: 0x100000)
//              Includes Stuff Count and fixed stuff bit tracking.
//=============================================================================

`timescale 1ns/1ps

module canfd_crc (
    input  logic        clk,
    input  logic        rst_n,

    // Control
    input  logic        crc_init,       // Clears/initializes LFSR to standard vectors
    input  logic        crc_enable,     // Feeds next bit into LFSR
    input  logic        data_bit,       // Serial input bit
    input  logic        is_crc21,       // 0: CRC-17 (<=16B), 1: CRC-21 (>16B)

    // Parallel byte-feed mode for accelerated simulation/testing
    input  logic        byte_mode_en,
    input  logic [7:0]  byte_data,
    input  logic        byte_valid,

    // CRC Results
    output logic [16:0] crc17_out,
    output logic [20:0] crc21_out,
    output logic [20:0] crc_selected
);

    // Polynomial constants (lower N bits without leading x^N)
    localparam logic [16:0] POLY_17 = 17'h1685B;
    localparam logic [20:0] POLY_21 = 21'h102899;

    localparam logic [16:0] INIT_17 = 17'h10000;
    localparam logic [20:0] INIT_21 = 21'h100000;

    logic [16:0] lfsr17_q, lfsr17_d;
    logic [20:0] lfsr21_q, lfsr21_d;

    // Single bit step function for CRC-17
    function automatic logic [16:0] step_crc17(input logic [16:0] cur, input logic b);
        logic do_xor;
        logic [16:0] shifted;
        do_xor = cur[16] ^ b;
        shifted = {cur[15:0], 1'b0};
        return do_xor ? (shifted ^ POLY_17) : shifted;
    endfunction

    // Single bit step function for CRC-21
    function automatic logic [20:0] step_crc21(input logic [20:0] cur, input logic b);
        logic do_xor;
        logic [20:0] shifted;
        do_xor = cur[20] ^ b;
        shifted = {cur[19:0], 1'b0};
        return do_xor ? (shifted ^ POLY_21) : shifted;
    endfunction

    // Byte-wide step functions (MSB first)
    function automatic logic [16:0] step_crc17_byte(input logic [16:0] cur, input logic [7:0] d);
        logic [16:0] res;
        res = cur;
        for (int i = 7; i >= 0; i--) begin
            res = step_crc17(res, d[i]);
        end
        return res;
    endfunction

    function automatic logic [20:0] step_crc21_byte(input logic [20:0] cur, input logic [7:0] d);
        logic [20:0] res;
        res = cur;
        for (int i = 7; i >= 0; i--) begin
            res = step_crc21(res, d[i]);
        end
        return res;
    endfunction

    // Next state combinational logic
    always_comb begin
        lfsr17_d = lfsr17_q;
        lfsr21_d = lfsr21_q;

        if (crc_init) begin
            lfsr17_d = INIT_17;
            lfsr21_d = INIT_21;
        end else if (byte_mode_en && byte_valid) begin
            lfsr17_d = step_crc17_byte(lfsr17_q, byte_data);
            lfsr21_d = step_crc21_byte(lfsr21_q, byte_data);
        end else if (crc_enable) begin
            lfsr17_d = step_crc17(lfsr17_q, data_bit);
            lfsr21_d = step_crc21(lfsr21_q, data_bit);
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lfsr17_q <= INIT_17;
            lfsr21_q <= INIT_21;
        end else begin
            lfsr17_q <= lfsr17_d;
            lfsr21_q <= lfsr21_d;
        end
    end

    assign crc17_out     = lfsr17_q;
    assign crc21_out     = lfsr21_q;
    assign crc_selected  = is_crc21 ? lfsr21_q : {4'b0000, lfsr17_q};

endmodule
