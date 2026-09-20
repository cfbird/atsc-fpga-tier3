// ============================================================================
// Module: atsc_rx_tier3_top
// Target: Xilinx Spartan-6 XC6SLX150 (USRP B210)
// Description:
//   Top-Level Full Physical-Layer ATSC 8VSB Receiver Core (Tier 3 Radio-on-Chip).
//   Directly demodulates AD9361 complex baseband I/Q to 188-byte MPEG-TS packets.
// ============================================================================

`timescale 1ns / 1ps

module atsc_rx_tier3_top #(
    parameter DATA_WIDTH = 16
)(
    input  wire                   clk,           // Master FPGA DSP Clock (47.35 MHz)
    input  wire                   rst_n,         // Active-low global reset
    
    // Complex I/Q Baseband Input from AD9361 RFIC (11.838462 MSps)
    input  wire                   in_valid,
    input  wire signed [DATA_WIDTH-1:0] in_i,
    input  wire signed [DATA_WIDTH-1:0] in_q,
    
    // MPEG Transport Stream Output to USB 3.0 FIFO / Host (19.39 Mbps)
    output wire                   out_ts_valid,
    output wire [7:0]             out_ts_byte,
    output wire                   out_ts_sync_strobe,
    
    // Diagnostic / Lock Status Signals
    output wire                   fpll_locked,
    output wire                   field_sync_detected
);

    // ------------------------------------------------------------------------
    // Stage 1: 50-Tap RRC Matched Filter
    // ------------------------------------------------------------------------
    wire rrc_valid;
    wire signed [DATA_WIDTH-1:0] rrc_i, rrc_q;
    atsc_rrc_filter #(.DATA_WIDTH(DATA_WIDTH)) u_rrc (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid), .in_i(in_i), .in_q(in_q),
        .out_valid(rrc_valid), .out_i(rrc_i), .out_q(rrc_q)
    );

    // ------------------------------------------------------------------------
    // Stage 2: Carrier FPLL & Q-Channel Discard
    // ------------------------------------------------------------------------
    wire fpll_valid;
    wire signed [DATA_WIDTH-1:0] fpll_real, fpll_q_err;
    atsc_fpll_qdiscard #(.DATA_WIDTH(DATA_WIDTH)) u_fpll (
        .clk(clk), .rst_n(rst_n),
        .in_valid(rrc_valid), .in_i(rrc_i), .in_q(rrc_q),
        .out_valid(fpll_valid), .out_real(fpll_real), .out_q_err(fpll_q_err),
        .lock_detect(fpll_locked)
    );

    // ------------------------------------------------------------------------
    // Stage 3: DC Blocker & Power-Normalizing AGC
    // ------------------------------------------------------------------------
    wire agc_valid;
    wire signed [DATA_WIDTH-1:0] agc_symbol;
    atsc_dc_blocker_agc #(.DATA_WIDTH(DATA_WIDTH)) u_dc_agc (
        .clk(clk), .rst_n(rst_n),
        .in_valid(fpll_valid), .in_real(fpll_real),
        .out_valid(agc_valid), .out_norm(agc_symbol)
    );

    // ------------------------------------------------------------------------
    // Stage 4: Symbol Timing Recovery (11.838 MSps -> 10.762 MSps)
    // ------------------------------------------------------------------------
    wire timing_valid;
    wire signed [DATA_WIDTH-1:0] timing_symbol;
    atsc_sync_timing #(.DATA_WIDTH(DATA_WIDTH)) u_timing (
        .clk(clk), .rst_n(rst_n),
        .in_valid(agc_valid), .in_sample(agc_symbol),
        .out_sym_strobe(timing_valid), .out_symbol(timing_symbol)
    );

    // ------------------------------------------------------------------------
    // Stage 5: Field Sync Checker & Segment Framer
    // ------------------------------------------------------------------------
    wire fs_valid, is_field_sync, field_num;
    wire signed [DATA_WIDTH-1:0] fs_symbol;
    wire [9:0] sym_idx;
    atsc_fs_checker #(.DATA_WIDTH(DATA_WIDTH)) u_fs_checker (
        .clk(clk), .rst_n(rst_n),
        .in_sym_valid(timing_valid), .in_symbol(timing_symbol),
        .out_seg_valid(fs_valid), .out_sym_data(fs_symbol),
        .out_sym_idx(sym_idx), .out_is_field_sync(is_field_sync),
        .out_field_num(field_num)
    );
    assign field_sync_detected = is_field_sync;

    // ------------------------------------------------------------------------
    // Stage 6: LMS Adaptive Channel Equalizer (24 Taps)
    // ------------------------------------------------------------------------
    wire eq_valid;
    wire signed [DATA_WIDTH-1:0] eq_symbol;
    wire signed [2:0] eq_sliced_level;
    wire [9:0] eq_sym_idx;
    wire eq_is_field_sync;
    atsc_equalizer #(.DATA_WIDTH(DATA_WIDTH), .NUM_TAPS(24)) u_equalizer (
        .clk(clk), .rst_n(rst_n),
        .in_valid(fs_valid), .in_sym(fs_symbol), .in_sym_idx(sym_idx),
        .in_is_field_sync(is_field_sync),
        .out_valid(eq_valid), .out_equalized_sym(eq_symbol),
        .out_sliced_level(eq_sliced_level),
        .out_sym_idx(eq_sym_idx),
        .out_is_field_sync(eq_is_field_sync)
    );

    // ------------------------------------------------------------------------
    // Stage 7: 12-Phase Parallel Rate-2/3 Trellis Slicer & Decoder
    // ------------------------------------------------------------------------
    wire vit_byte_valid;
    wire [7:0] vit_byte, vit_byte_idx;
    atsc_viterbi_decoder #(.DATA_WIDTH(DATA_WIDTH)) u_viterbi (
        .clk(clk), .rst_n(rst_n),
        .in_valid(eq_valid), .in_soft_sym(eq_symbol), .in_sym_idx(eq_sym_idx),
        .in_is_field_sync(eq_is_field_sync),
        .out_byte_valid(vit_byte_valid), .out_codeword_byte(vit_byte),
        .out_byte_idx(vit_byte_idx)
    );

    // ------------------------------------------------------------------------
    // Stage 8: 52-Branch Convolutional Deinterleaver
    // ------------------------------------------------------------------------
    wire deint_valid;
    wire [7:0] deint_byte;
    atsc_deinterleaver u_deinterleaver (
        .clk(clk), .rst_n(rst_n),
        .in_field_sync(eq_is_field_sync),
        .in_byte_valid(vit_byte_valid), .in_byte(vit_byte),
        .out_byte_valid(deint_valid), .out_byte(deint_byte)
    );

    // ------------------------------------------------------------------------
    // Stage 9: Reed-Solomon RS(207, 187, t=10) Error Correction Decoder
    // ------------------------------------------------------------------------
    wire rs_valid, rs_err;
    wire [7:0] rs_byte;
    atsc_rs_decoder u_rs_decoder (
        .clk(clk), .rst_n(rst_n),
        .in_byte_valid(deint_valid), .in_byte(deint_byte),
        .out_byte_valid(rs_valid), .out_byte(rs_byte),
        .out_uncorrectable_err(rs_err)
    );

    // ------------------------------------------------------------------------
    // Stage 10: PRBS Galois LFSR Derandomizer
    // ------------------------------------------------------------------------
    wire derand_valid;
    wire [7:0] derand_byte;
    atsc_derandomizer u_derandomizer (
        .clk(clk), .rst_n(rst_n),
        .in_field_sync_strobe(1'b0),
        .in_byte_valid(rs_valid), .in_byte(rs_byte),
        .out_byte_valid(derand_valid), .out_byte(derand_byte)
    );

    // ------------------------------------------------------------------------
    // Stage 11: MPEG-TS Depadder (0x47 Sync Insertion -> 188-byte Packets)
    // ------------------------------------------------------------------------
    atsc_depad u_depad (
        .clk(clk), .rst_n(rst_n),
        .in_byte_valid(derand_valid), .in_byte(derand_byte),
        .out_ts_valid(out_ts_valid), .out_ts_byte(out_ts_byte),
        .out_ts_sync_strobe(out_ts_sync_strobe)
    );

endmodule
