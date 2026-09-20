// ============================================================================
// Module: atsc_tx_tier3_top
// Standard: ATSC A/53 Part 2 (8VSB Terrestrial Broadcast)
// Target: Xilinx Spartan-6 XC6SLX150 (USRP B210)
// Description:
//   Top-Level Full Physical-Layer ATSC 8VSB Broadcast Modulator (Tier 3 TX Radio-on-Chip).
//   Directly modulates 188-byte MPEG-TS packets into complex baseband I/Q for AD9361 TX DAC.
// ============================================================================

`timescale 1ns / 1ps
`include "atsc_constants.vh"

module atsc_tx_tier3_top #(
    parameter DATA_WIDTH = 16
)(
    input  wire                   clk,           // Master FPGA DSP Clock (47.35 MHz)
    input  wire                   rst_n,         // Active-low global reset
    
    // MPEG-TS Packet Input from USB 3.0 / Host (188-byte packets, 19.39 Mbps)
    input  wire                   in_ts_valid,
    input  wire [7:0]             in_ts_byte,
    input  wire                   in_ts_pkt_start,
    input  wire                   in_ts_field_start,
    
    // Complex 8VSB Baseband I/Q Output to AD9361 TX DAC (~10.76 MSps)
    output wire                   out_iq_valid,
    output wire signed [DATA_WIDTH-1:0] out_i,
    output wire signed [DATA_WIDTH-1:0] out_q,
    
    // Diagnostic / Status Flags
    output wire                   out_field_num,
    output wire [8:0]             out_seg_num,
    output wire                   out_is_sync
);

    // ------------------------------------------------------------------------
    // Stage 1: PRBS Data Randomizer (g(X) = X^14 + X^11 + 1)
    // ------------------------------------------------------------------------
    wire rand_valid, rand_field_start, rand_seg_start;
    wire [7:0] rand_byte, rand_byte_idx;
    atsc_tx_randomizer u_randomizer (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_ts_valid), .in_byte(in_ts_byte),
        .in_pkt_start(in_ts_pkt_start), .in_field_start(in_ts_field_start),
        .out_valid(rand_valid), .out_byte(rand_byte),
        .out_byte_idx(rand_byte_idx), .out_field_start(rand_field_start),
        .out_seg_start(rand_seg_start)
    );

    // ------------------------------------------------------------------------
    // Stage 2: Reed-Solomon RS(207,187, t=10) Encoder
    // ------------------------------------------------------------------------
    wire rs_valid, rs_field_start, rs_seg_start;
    wire [7:0] rs_byte, rs_byte_idx;
    atsc_tx_rs_encoder u_rs_encoder (
        .clk(clk), .rst_n(rst_n),
        .in_valid(rand_valid), .in_byte(rand_byte),
        .in_byte_idx(rand_byte_idx), .in_field_start(rand_field_start),
        .in_seg_start(rand_seg_start),
        .out_valid(rs_valid), .out_byte(rs_byte),
        .out_byte_idx(rs_byte_idx), .out_field_start(rs_field_start),
        .out_seg_start(rs_seg_start)
    );

    // ------------------------------------------------------------------------
    // Stage 3: 52-Branch Convolutional Byte Interleaver
    // ------------------------------------------------------------------------
    wire int_valid, int_field_start, int_seg_start;
    wire [7:0] int_byte, int_byte_idx;
    atsc_tx_interleaver u_interleaver (
        .clk(clk), .rst_n(rst_n),
        .in_valid(rs_valid), .in_byte(rs_byte),
        .in_byte_idx(rs_byte_idx), .in_field_start(rs_field_start),
        .in_seg_start(rs_seg_start),
        .out_valid(int_valid), .out_byte(int_byte),
        .out_byte_idx(int_byte_idx), .out_field_start(int_field_start),
        .out_seg_start(int_seg_start)
    );

    // ------------------------------------------------------------------------
    // Stage 4: 12-Phase Parallel Trellis Coder & 8-Level Mapper
    // ------------------------------------------------------------------------
    wire tc_valid, tc_field_start, tc_seg_start;
    wire signed [DATA_WIDTH-1:0] tc_symbol;
    wire [9:0] tc_sym_idx;
    atsc_tx_trellis_encoder #(.DATA_WIDTH(DATA_WIDTH)) u_trellis (
        .clk(clk), .rst_n(rst_n),
        .in_valid(int_valid), .in_byte(int_byte),
        .in_byte_idx(int_byte_idx), .in_field_start(int_field_start),
        .in_seg_start(int_seg_start),
        .out_valid(tc_valid), .out_symbol(tc_symbol),
        .out_sym_idx(tc_sym_idx), .out_field_start(tc_field_start),
        .out_seg_start(tc_seg_start)
    );

    // ------------------------------------------------------------------------
    // Stage 5: Segment Sync & PN511/PN63 Field Sync Multiplexer
    // ------------------------------------------------------------------------
    wire sync_valid, sync_field_num, sync_is_sync;
    wire signed [DATA_WIDTH-1:0] sync_symbol;
    wire [9:0] sync_sym_idx;
    wire [8:0] sync_seg_num;
    atsc_tx_sync_mux #(.DATA_WIDTH(DATA_WIDTH)) u_sync_mux (
        .clk(clk), .rst_n(rst_n),
        .in_valid(tc_valid), .in_symbol(tc_symbol),
        .in_sym_idx(tc_sym_idx), .in_field_start(tc_field_start),
        .in_seg_start(tc_seg_start),
        .out_valid(sync_valid), .out_symbol(sync_symbol),
        .out_sym_idx(sync_sym_idx), .out_seg_num(sync_seg_num),
        .out_field_num(sync_field_num), .out_is_sync(sync_is_sync)
    );
    assign out_field_num = sync_field_num;
    assign out_seg_num   = sync_seg_num;
    assign out_is_sync   = sync_is_sync;

    // ------------------------------------------------------------------------
    // Stage 6: Pilot DC Offset Inserter (+1.25)
    // ------------------------------------------------------------------------
    wire pilot_valid, pilot_is_sync;
    wire signed [DATA_WIDTH-1:0] pilot_symbol;
    wire [9:0] pilot_sym_idx;
    wire [8:0] pilot_seg_num;
    wire pilot_field_num;
    atsc_tx_pilot_adder #(.DATA_WIDTH(DATA_WIDTH)) u_pilot (
        .clk(clk), .rst_n(rst_n),
        .in_valid(sync_valid), .in_symbol(sync_symbol),
        .in_sym_idx(sync_sym_idx), .in_seg_num(sync_seg_num),
        .in_field_num(sync_field_num), .in_is_sync(sync_is_sync),
        .out_valid(pilot_valid), .out_symbol(pilot_symbol),
        .out_sym_idx(pilot_sym_idx), .out_seg_num(pilot_seg_num),
        .out_field_num(pilot_field_num), .out_is_sync(pilot_is_sync)
    );

    // ------------------------------------------------------------------------
    // Stage 7: Complex 8VSB Pulse Shaping Filter (RRC In-Phase + Hilbert)
    // ------------------------------------------------------------------------
    atsc_tx_rrc_filter #(.DATA_WIDTH(DATA_WIDTH), .NUM_TAPS(31)) u_rrc_filter (
        .clk(clk), .rst_n(rst_n),
        .in_valid(pilot_valid), .in_symbol(pilot_symbol),
        .out_valid(out_iq_valid), .out_i(out_i), .out_q(out_q)
    );

endmodule
