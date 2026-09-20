// ============================================================================
// File: atsc_constants.vh
// Description: ATSC A/53 8VSB Standard Hardware Constants & Parameters
// Target: Xilinx Spartan-6 XC6SLX150 (USRP B210) / 7-Series / UltraScale
// ============================================================================

`ifndef ATSC_CONSTANTS_VH
`define ATSC_CONSTANTS_VH

// Symbol Rates & Dimensions
`define ATSC_SYMBOL_RATE_NUM     4500000.0 * 684.0  // ~10.762238 MHz
`define ATSC_SYMBOL_RATE_DEN     286.0
`define ATSC_SYMBOLS_PER_SEG     832                // 4 sync + 828 data symbols
`define ATSC_SEGS_PER_FIELD      313                // 1 field sync + 312 data segs
`define ATSC_FIELDS_PER_FRAME    2

// Packet & Codeword Lengths (Bytes)
`define ATSC_RS_CODEWORD_LEN     207                // RS(207, 187, t=10)
`define ATSC_RS_DATA_LEN         187                // Data payload per segment
`define ATSC_MPEG_PKT_LEN        188                // 1 sync (0x47) + 187 data
`define ATSC_SYNC_BYTE           8'h47

// Segment Sync Symbol Pattern (Nominal levels: +5, -5, -5, +5)
`define ATSC_SEG_SYNC_0          3'b110             // +5
`define ATSC_SEG_SYNC_1          3'b001             // -5
`define ATSC_SEG_SYNC_2          3'b001             // -5
`define ATSC_SEG_SYNC_3          3'b110             // +5

// Interleaver Parameters
`define ATSC_INTERLEAVER_BRANCHES 52
`define ATSC_INTERLEAVER_DELAY    4                 // M = 4 bytes per branch

// Galois Field GF(2^8) Generator Polynomial: p(X) = X^8 + X^4 + X^3 + X^2 + 1 (0x11D)
`define ATSC_GF_POLY             9'h11D

// PRBS Derandomizer Galois Generator: g(X) = X^14 + X^11 + 1
// Initial preload word for Field 1: 0x018F, Field 2: 0x018F (inverted on first byte)
`define ATSC_PRBS_PRELOAD        14'h018F

`endif // ATSC_CONSTANTS_VH
