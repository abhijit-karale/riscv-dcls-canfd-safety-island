//=============================================================================
// File: async_fifo_gray.sv
// Description: Production-grade Dual-Clock Asynchronous FIFO with Gray-Code
//              Pointers and Multi-Stage Flop Synchronizers.
// Standard: IEEE 1800-2017 SystemVerilog
// Target: ASIC / FPGA Automotive ASIL-D Safe Clock Domain Crossing (CDC)
//=============================================================================

`timescale 1ns/1ps

module async_fifo_gray #(
    parameter int DATA_WIDTH     = 32,
    parameter int ADDR_DEPTH     = 16,
    parameter int ALMOST_FULL_THRESH  = 14,
    parameter int ALMOST_EMPTY_THRESH = 2,
    parameter int SYNC_STAGES    = 2
)(
    // Write Domain
    input  logic                   wclk,
    input  logic                   wrst_n,
    input  logic                   winc,
    input  logic [DATA_WIDTH-1:0]  wdata,
    output logic                   wfull,
    output logic                   walmost_full,

    // Read Domain
    input  logic                   rclk,
    input  logic                   rrst_n,
    input  logic                   rinc,
    output logic [DATA_WIDTH-1:0]  rdata,
    output logic                   rempty,
    output logic                   ralmost_empty
);

    localparam int ADDR_WIDTH = $clog2(ADDR_DEPTH);

    // Memory array
    logic [DATA_WIDTH-1:0] mem [0:ADDR_DEPTH-1];

    // Write domain signals
    logic [ADDR_WIDTH:0] wbin_q, wbin_d;
    logic [ADDR_WIDTH:0] wptr_gray_q, wptr_gray_d;
    logic [ADDR_WIDTH:0] rptr_gray_sync_wclk [SYNC_STAGES];
    logic [ADDR_WIDTH:0] rbin_wclk;

    // Read domain signals
    logic [ADDR_WIDTH:0] rbin_q, rbin_d;
    logic [ADDR_WIDTH:0] rptr_gray_q, rptr_gray_d;
    logic [ADDR_WIDTH:0] wptr_gray_sync_rclk [SYNC_STAGES];
    logic [ADDR_WIDTH:0] wbin_rclk;

    // Functions for Gray/Binary conversion
    function automatic logic [ADDR_WIDTH:0] bin2gray(input logic [ADDR_WIDTH:0] bin);
        return bin ^ (bin >> 1);
    endfunction

    function automatic logic [ADDR_WIDTH:0] gray2bin(input logic [ADDR_WIDTH:0] gray);
        logic [ADDR_WIDTH:0] bin;
        bin = gray;
        for (int i = 1; i <= ADDR_WIDTH; i = i << 1) begin
            bin = bin ^ (bin >> i);
        end
        return bin;
    endfunction

    //-------------------------------------------------------------------------
    // Memory Write & Read
    //-------------------------------------------------------------------------
    wire w_en = winc & ~wfull;
    wire r_en = rinc & ~rempty;

    always_ff @(posedge wclk) begin
        if (w_en) begin
            mem[wbin_q[ADDR_WIDTH-1:0]] <= wdata;
        end
    end

    // Direct registered or combinational read output (lookahead read)
    assign rdata = mem[rbin_q[ADDR_WIDTH-1:0]];

    //-------------------------------------------------------------------------
    // Write Domain Pointer & Status Logic
    //-------------------------------------------------------------------------
    assign wbin_d      = wbin_q + (w_en ? 1'b1 : 1'b0);
    assign wptr_gray_d = bin2gray(wbin_d);

    always_ff @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            wbin_q      <= '0;
            wptr_gray_q <= '0;
        end else begin
            wbin_q      <= wbin_d;
            wptr_gray_q <= wptr_gray_d;
        end
    end

    // Full condition:
    // MSB differs, 2nd MSB differs, remaining bits match
    wire [ADDR_WIDTH:0] rptr_wclk = rptr_gray_sync_wclk[SYNC_STAGES-1];
    wire wfull_val = (wptr_gray_d == {~rptr_wclk[ADDR_WIDTH:ADDR_WIDTH-1], rptr_wclk[ADDR_WIDTH-2:0]});

    always_ff @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            wfull <= 1'b0;
        end else begin
            wfull <= wfull_val;
        end
    end

    // Almost full logic in write domain
    assign rbin_wclk = gray2bin(rptr_wclk);
    wire [ADDR_WIDTH:0] w_occupancy = wbin_q - rbin_wclk;

    always_ff @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            walmost_full <= 1'b0;
        end else begin
            walmost_full <= (w_occupancy >= ALMOST_FULL_THRESH[ADDR_WIDTH:0]);
        end
    end

    //-------------------------------------------------------------------------
    // Read Domain Pointer & Status Logic
    //-------------------------------------------------------------------------
    assign rbin_d      = rbin_q + (r_en ? 1'b1 : 1'b0);
    assign rptr_gray_d = bin2gray(rbin_d);

    always_ff @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            rbin_q      <= '0;
            rptr_gray_q <= '0;
        end else begin
            rbin_q      <= rbin_d;
            rptr_gray_q <= rptr_gray_d;
        end
    end

    // Empty condition: read Gray pointer equals synchronized write Gray pointer
    wire [ADDR_WIDTH:0] wptr_rclk = wptr_gray_sync_rclk[SYNC_STAGES-1];
    wire rempty_val = (rptr_gray_d == wptr_rclk);

    always_ff @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            rempty <= 1'b1;
        end else begin
            rempty <= rempty_val;
        end
    end

    // Almost empty logic in read domain
    assign wbin_rclk = gray2bin(wptr_rclk);
    wire [ADDR_WIDTH:0] r_occupancy = wbin_rclk - rbin_q;

    always_ff @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            ralmost_empty <= 1'b1;
        end else begin
            ralmost_empty <= (r_occupancy <= ALMOST_EMPTY_THRESH[ADDR_WIDTH:0]);
        end
    end

    //-------------------------------------------------------------------------
    // Dual-Stage Flop Synchronizers (with ASYNC_REG attributes)
    //-------------------------------------------------------------------------
    // Synchronize rptr_gray into wclk domain
    (* ASYNC_REG = "TRUE" *) logic [ADDR_WIDTH:0] rptr_sync_regs [SYNC_STAGES];
    always_ff @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            for (int s = 0; s < SYNC_STAGES; s++) begin
                rptr_sync_regs[s] <= '0;
            end
        end else begin
            rptr_sync_regs[0] <= rptr_gray_q;
            for (int s = 1; s < SYNC_STAGES; s++) begin
                rptr_sync_regs[s] <= rptr_sync_regs[s-1];
            end
        end
    end
    assign rptr_gray_sync_wclk = rptr_sync_regs;

    // Synchronize wptr_gray into rclk domain
    (* ASYNC_REG = "TRUE" *) logic [ADDR_WIDTH:0] wptr_sync_regs [SYNC_STAGES];
    always_ff @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            for (int s = 0; s < SYNC_STAGES; s++) begin
                wptr_sync_regs[s] <= '0;
            end
        end else begin
            wptr_sync_regs[0] <= wptr_gray_q;
            for (int s = 1; s < SYNC_STAGES; s++) begin
                wptr_sync_regs[s] <= wptr_sync_regs[s-1];
            end
        end
    end
    assign wptr_gray_sync_rclk = wptr_sync_regs;

endmodule
