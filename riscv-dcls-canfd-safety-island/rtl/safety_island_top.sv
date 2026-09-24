 //=============================================================================
// File: safety_island_top.sv
// Description: Production-grade Dual-Core Lockstep (DCLS) Automotive Safety Island
//              Top-Level SoC Integration.
//              - Core Domain: 200 MHz Lockstep RISC-V RV32I (Master + Shadow)
//              - Peripheral Domain: 40 MHz CAN-FD Controller
//              - CDC Boundary: Gray-Code Dual-Clock Asynchronous FIFOs
//              - ISO 26262 ASIL-D Hardware Safe-State Clamp Multiplexers
//=============================================================================

`timescale 1ns/1ps

import rv32i_pkg::*;

module safety_island_top #(
    parameter int MEM_SIZE_WORDS = 1024 // 4 KB Instruction and Data Memories
)(
    // Clocks and Resets
    input  logic        clk_core,           // 200 MHz Core Domain Clock
    input  logic        rst_core_n,         // Active-low Core Reset
    input  logic        clk_can,            // 40 MHz Peripheral CAN Clock
    input  logic        rst_can_n,          // Active-low CAN Reset

    // Physical Automotive CAN Bus Interface
    output logic        can_tx,             // Transmit pin to CAN Transceiver
    input  logic        can_rx,             // Receive pin from CAN Transceiver

    // Functional Safety & Diagnostic Interface (ASIL-D)
    output logic        safe_state_alarm_o, // Hardware Safe-State Alarm
    output logic [31:0] fault_status_o,     // Captured Mismatch Vector
    output logic [31:0] fault_pc_o,         // Captured Fault PC
    input  logic        alarm_clear_n,      // Synchronous Alarm Clear

    // Hardware Fault Injection Unit (FIU) External Control
    input  logic        fiu_ext_en,
    input  logic        fiu_ext_target_shadow,
    input  logic [1:0]  fiu_ext_stage,
    input  logic [4:0]  fiu_ext_bit_idx,
    input  logic [31:0] fiu_ext_mask
);

    //=========================================================================
    // 1. Core Domain (200 MHz): Dual-Core Lockstep (DCLS) Subsystem
    //=========================================================================
    logic [31:0] core_imem_addr;
    logic        core_imem_req;
    logic [31:0] core_imem_rdata;

    logic [31:0] core_dmem_addr;
    logic [31:0] core_dmem_wdata;
    logic        core_dmem_we;
    logic [3:0]  core_dmem_be;
    logic        core_dmem_req;
    logic [31:0] core_dmem_rdata;

    logic        internal_alarm;
    logic [31:0] captured_pc;
    logic [31:0] captured_mismatch;
    logic [31:0] captured_timestamp;

    dcls_comparator #(
        .DELAY_CYCLES (2),
        .BOOT_PC      (32'h0000_0000)
    ) u_dcls_subsystem (
        .clk                 (clk_core),
        .rst_n               (rst_core_n),
        .imem_addr           (core_imem_addr),
        .imem_req            (core_imem_req),
        .imem_rdata          (core_imem_rdata),
        .dmem_addr           (core_dmem_addr),
        .dmem_wdata          (core_dmem_wdata),
        .dmem_we             (core_dmem_we),
        .dmem_be             (core_dmem_be),
        .dmem_req            (core_dmem_req),
        .dmem_rdata          (core_dmem_rdata),
        .safe_state_alarm    (internal_alarm),
        .fault_captured_pc   (captured_pc),
        .fault_mismatch_mask (captured_mismatch),
        .fault_timestamp     (captured_timestamp),
        .alarm_clear_n       (alarm_clear_n),
        .fiu_en              (fiu_ext_en),
        .fiu_target_shadow   (fiu_ext_target_shadow),
        .fiu_stage           (fiu_ext_stage),
        .fiu_bit_idx         (fiu_ext_bit_idx),
        .fiu_mask            (fiu_ext_mask)
    );

    //=========================================================================
    // 2. Fail-Safe Memory Write Protection Clamp
    //=========================================================================
    // If safe_state_alarm asserts, inhibit any further writes to memory
    wire safe_dmem_we = core_dmem_we & ~internal_alarm;

    //=========================================================================
    // 3. Local Instruction Memory / Boot ROM (Core Domain)
    //=========================================================================
    logic [31:0] imem [0:MEM_SIZE_WORDS-1];

    // Preload with an automotive safety loop program
    initial begin
        // Program Instructions:
        // 0x00: ADDI x1, x0, 10      -> 0x00A00093 (Loop counter = 10)
        // 0x04: ADDI x2, x0, 1       -> 0x00100113 (Increment = 1)
        // 0x08: ADD  x3, x3, x2      -> 0x002181B3 (x3 += 1)
        // 0x0C: SW   x3, 0(x0)       -> 0x00302023 (Store x3 to data memory 0x20000000)
        // 0x10: LW   x4, 0(x0)       -> 0x00002203 (Load x4 from data memory)
        // 0x14: BNE  x3, x1, -12     -> 0xFE119AE3 (Branch back to 0x08 if x3 != 10)
        // 0x18: SW   x3, 4(x0)       -> 0x00302223 (Store x3 to CAN TX trigger)
        // 0x1C: JAL  x0, -20         -> 0xFEDFF06F (Jump back to loop start)
        imem[0] = 32'h00A00093;
        imem[1] = 32'h00100113;
        imem[2] = 32'h002181B3;
        imem[3] = 32'h00302023;
        imem[4] = 32'h00002203;
        imem[5] = 32'hFE119AE3;
        imem[6] = 32'h00302223;
        imem[7] = 32'hFEDFF06F;
        for (int i = 8; i < MEM_SIZE_WORDS; i++) begin
            imem[i] = 32'h00000013; // NOP (ADDI x0, x0, 0)
        end
    end

    // Instruction Memory Read (registered or comb)
    always_ff @(posedge clk_core) begin
        if (core_imem_req) begin
            core_imem_rdata <= imem[core_imem_addr[11:2]];
        end
    end

    //=========================================================================
    // 4. Memory-Mapped Address Decoder & Peripherals (Core Domain)
    //=========================================================================
    // Address Map:
    // 0x0000_0000 .. 0x0000_0FFF : Boot Instruction Memory (Alias / Mirror)
    // 0x2000_0000 .. 0x2000_0FFF : Data RAM (4KB)
    // 0x4000_0000                 : Safety Alarm & Status Register
    // 0x4000_0004                 : Fault PC Register
    // 0x4000_0008                 : Fault Timestamp Register
    // 0x4000_0100                 : CAN TX FIFO Data Port (Write)
    // 0x4000_0104                 : CAN TX Command / Start
    // 0x4000_0108                 : CAN RX FIFO Data Port (Read)
    // 0x4000_010C                 : CAN Status Register

    logic [31:0] dmem [0:MEM_SIZE_WORDS-1];
    logic [31:0] dmem_read_data;

    // RAM Write
    always_ff @(posedge clk_core) begin
        if (safe_dmem_we && (core_dmem_addr[31:28] == 4'h2 || core_dmem_addr[31:28] == 4'h0)) begin
            if (core_dmem_be[0]) dmem[core_dmem_addr[11:2]][7:0]   <= core_dmem_wdata[7:0];
            if (core_dmem_be[1]) dmem[core_dmem_addr[11:2]][15:8]  <= core_dmem_wdata[15:8];
            if (core_dmem_be[2]) dmem[core_dmem_addr[11:2]][23:16] <= core_dmem_wdata[23:16];
            if (core_dmem_be[3]) dmem[core_dmem_addr[11:2]][31:24] <= core_dmem_wdata[31:24];
        end
    end

    assign dmem_read_data = dmem[core_dmem_addr[11:2]];

    // CDC TX FIFO Write signals (200 MHz core domain)
    logic        tx_fifo_winc;
    logic [31:0] tx_fifo_wdata;
    logic        tx_fifo_wfull;
    logic        tx_fifo_walmost_full;

    // CDC RX FIFO Read signals (200 MHz core domain)
    logic        rx_fifo_rinc;
    logic [31:0] rx_fifo_rdata;
    logic        rx_fifo_rempty;
    logic        rx_fifo_ralmost_empty;

    // MMIO read decode
    always_comb begin
        if (core_dmem_addr[31:16] == 16'h4000) begin
            case (core_dmem_addr[7:0])
                8'h00: core_dmem_rdata = {31'd0, internal_alarm};
                8'h04: core_dmem_rdata = captured_pc;
                8'h08: core_dmem_rdata = captured_timestamp;
                8'h08: core_dmem_rdata = rx_fifo_rdata;
                8'h0C: core_dmem_rdata = {30'd0, rx_fifo_rempty, tx_fifo_wfull};
                default: core_dmem_rdata = 32'd0;
            endcase
        end else begin
            core_dmem_rdata = dmem_read_data;
        end
    end

    // MMIO write to CAN TX FIFO & Commands
    logic can_tx_start_reg;
    always_ff @(posedge clk_core or negedge rst_core_n) begin
        if (!rst_core_n) begin
            tx_fifo_winc     <= 1'b0;
            tx_fifo_wdata    <= '0;
            can_tx_start_reg <= 1'b0;
            rx_fifo_rinc     <= 1'b0;
        end else begin
            tx_fifo_winc     <= 1'b0;
            can_tx_start_reg <= 1'b0;
            rx_fifo_rinc     <= 1'b0;

            if (safe_dmem_we && (core_dmem_addr == 32'h4000_0100)) begin
                tx_fifo_wdata <= core_dmem_wdata;
                tx_fifo_winc  <= 1'b1;
            end
            if (safe_dmem_we && (core_dmem_addr == 32'h4000_0104)) begin
                can_tx_start_reg <= core_dmem_wdata[0];
            end
            if (core_dmem_req && !core_dmem_we && (core_dmem_addr == 32'h4000_0108)) begin
                rx_fifo_rinc <= 1'b1;
            end
        end
    end

    //=========================================================================
    // 5. Clock Domain Crossing (CDC) Asynchronous FIFOs
    //=========================================================================
    // TX FIFO: Core Domain (200 MHz) -> CAN Domain (40 MHz)
    logic [31:0] can_tx_fifo_rdata;
    logic        can_tx_fifo_rempty;
    logic        can_tx_fifo_rinc;

    async_fifo_gray #(
        .DATA_WIDTH (32),
        .ADDR_DEPTH (16)
    ) u_tx_cdc_fifo (
        .wclk          (clk_core),
        .wrst_n        (rst_core_n),
        .winc          (tx_fifo_winc),
        .wdata         (tx_fifo_wdata),
        .wfull         (tx_fifo_wfull),
        .walmost_full  (tx_fifo_walmost_full),
        .rclk          (clk_can),
        .rrst_n        (rst_can_n),
        .rinc          (can_tx_fifo_rinc),
        .rdata         (can_tx_fifo_rdata),
        .rempty        (can_tx_fifo_rempty),
        .ralmost_empty ()
    );

    // RX FIFO: CAN Domain (40 MHz) -> Core Domain (200 MHz)
    logic [31:0] can_rx_packet_data;
    logic        can_rx_packet_valid;
    logic        can_rx_fifo_wfull;

    async_fifo_gray #(
        .DATA_WIDTH (32),
        .ADDR_DEPTH (16)
    ) u_rx_cdc_fifo (
        .wclk          (clk_can),
        .wrst_n        (rst_can_n),
        .winc          (can_rx_packet_valid && !can_rx_fifo_wfull),
        .wdata         (can_rx_packet_data),
        .wfull         (can_rx_fifo_wfull),
        .walmost_full  (),
        .rclk          (clk_core),
        .rrst_n        (rst_core_n),
        .rinc          (rx_fifo_rinc),
        .rdata         (rx_fifo_rdata),
        .rempty        (rx_fifo_rempty),
        .ralmost_empty (rx_fifo_ralmost_empty)
    );

    // Synchronize CAN TX Start pulse into 40 MHz CAN domain
    logic tx_start_sync0, tx_start_sync1;
    always_ff @(posedge clk_can or negedge rst_can_n) begin
        if (!rst_can_n) begin
            tx_start_sync0 <= 1'b0;
            tx_start_sync1 <= 1'b0;
        end else begin
            tx_start_sync0 <= can_tx_start_reg;
            tx_start_sync1 <= tx_start_sync0;
        end
    end

    //=========================================================================
    // 6. CAN-FD Peripheral Subsystem (40 MHz Domain)
    //=========================================================================
    logic raw_can_tx;
    logic can_tx_ready;
    logic can_tx_done;
    logic can_rx_done;

    assign can_tx_fifo_rinc = !can_tx_fifo_rempty && can_tx_ready;

    canfd_top #(
        .DEFAULT_NOM_BRP  (4),
        .DEFAULT_DATA_BRP (1)
    ) u_canfd_core (
        .clk              (clk_can),
        .rst_n            (rst_can_n),
        .can_tx           (raw_can_tx),
        .can_rx           (can_rx),
        .tx_data_in       (can_tx_fifo_rdata),
        .tx_data_valid    (!can_tx_fifo_rempty),
        .tx_data_ready    (can_tx_ready),
        .tx_start_req     (tx_start_sync1),
        .rx_data_out      (can_rx_packet_data),
        .rx_data_valid    (can_rx_packet_valid),
        .rx_data_ready    (!can_rx_fifo_wfull),
        .ctrl_loopback_en (1'b0),
        .ctrl_brs_en      (1'b1),
        .ctrl_tx_id       (29'h123),
        .ctrl_tx_ide      (1'b0),
        .ctrl_tx_dlc      (4'd15), // 64-byte payload
        .ctrl_nom_brp     (8'd4),
        .ctrl_data_brp    (8'd1),
        .stat_tx_busy     (),
        .stat_rx_done     (can_rx_done),
        .stat_tx_done     (can_tx_done),
        .stat_crc_err     (),
        .stat_bus_off     (),
        .stat_tec         (),
        .stat_rec         ()
    );

    // Synchronize safe_state_alarm into 40 MHz CAN domain for immediate bus isolation
    logic alarm_sync_can0, alarm_sync_can1;
    always_ff @(posedge clk_can or negedge rst_can_n) begin
        if (!rst_can_n) begin
            alarm_sync_can0 <= 1'b0;
            alarm_sync_can1 <= 1'b0;
        end else begin
            alarm_sync_can0 <= internal_alarm;
            alarm_sync_can1 <= alarm_sync_can0;
        end
    end

    //=========================================================================
    // 7. Hardware Safe-State Clamp Multiplexer (ASIL-D Bus Isolation)
    //=========================================================================
    // If alarm asserts in either domain, clamp CAN TX to recessive (1'b1)
    // prevents "babbling idiot" node from disturbing safety-critical vehicle bus.
    wire safety_isolate = internal_alarm | alarm_sync_can1;

    assign can_tx             = safety_isolate ? 1'b1 : raw_can_tx;
    assign safe_state_alarm_o = internal_alarm;
    assign fault_status_o     = captured_mismatch;
    assign fault_pc_o         = captured_pc;

endmodule
