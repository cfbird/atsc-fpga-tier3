// ============================================================================
// Module: atsc_tx_sync_mux
// Standard: ATSC A/53 Part 2 (8VSB Terrestrial Broadcast)
// Target: Xilinx Spartan-6 XC6SLX150 (USRP B210)
// Description:
//   Segment Sync and Field Sync Multiplexer.
//   - Inserts 4-symbol segment sync pattern (+5, -5, -5, +5) before each 828 data symbols.
//   - Inserts 832-symbol Field Sync segment (PN511 + 3x PN63 + VSB Mode + Precode)
//     every 312 data segments (313 segments per field, 2 fields per frame).
// ============================================================================

`timescale 1ns / 1ps
`include "atsc_constants.vh"

module atsc_tx_sync_mux #(
    parameter DATA_WIDTH = 16
)(
    input  wire        clk,
    input  wire        rst_n,
    
    // Input Data Symbols from Trellis Encoder (828 symbols / data segment)
    input  wire        in_valid,
    input  wire signed [DATA_WIDTH-1:0] in_symbol,
    input  wire [9:0]  in_sym_idx,
    input  wire        in_field_start,
    input  wire        in_seg_start,
    
    // Output 832-symbol Formatted Frame Stream
    output reg         out_valid,
    output reg  signed [DATA_WIDTH-1:0] out_symbol,
    output reg  [9:0]  out_sym_idx,     // 0..831
    output reg  [8:0]  out_seg_num,     // 0..312
    output reg         out_field_num,   // 0 or 1
    output reg         out_is_sync
);

    localparam signed [DATA_WIDTH-1:0] LVL_P5 =  16'sd2925;
    localparam signed [DATA_WIDTH-1:0] LVL_N5 = -16'sd2925;

    // Segment Sync ROM (4 symbols: +5, -5, -5, +5)
    wire signed [DATA_WIDTH-1:0] seg_sync_rom [0:3];
    assign seg_sync_rom[0] = LVL_P5;
    assign seg_sync_rom[1] = LVL_N5;
    assign seg_sync_rom[2] = LVL_N5;
    assign seg_sync_rom[3] = LVL_P5;

    // State Machine
    localparam ST_FIELD_SYNC = 2'd0;
    localparam ST_SEG_SYNC   = 2'd1;
    localparam ST_DATA       = 2'd2;

    reg [1:0] state;
    reg [9:0] sym_cnt;
    reg [8:0] seg_cnt;
    reg       cur_field;
    reg [8:0] pn511_lfsr;
    reg [5:0] pn63_lfsr;

    // PN511 generator: X^9 + X^7 + 1, preload 9'b100000000
    function pn511_next_bit;
        input [8:0] cur_state;
        begin
            pn511_next_bit = cur_state[8];
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= ST_FIELD_SYNC;
            sym_cnt       <= 10'd0;
            seg_cnt       <= 9'd0;
            cur_field     <= 1'b0;
            pn511_lfsr    <= 9'b100000000;
            pn63_lfsr     <= 6'b100000;
            out_valid     <= 1'b0;
            out_symbol    <= 16'sd0;
            out_sym_idx   <= 10'd0;
            out_seg_num   <= 9'd0;
            out_field_num <= 1'b0;
            out_is_sync   <= 1'b0;
        end else begin
            case (state)
                ST_FIELD_SYNC: begin
                    // Emit 832 Field Sync Symbols
                    out_valid     <= 1'b1;
                    out_sym_idx   <= sym_cnt;
                    out_seg_num   <= 9'd0;
                    out_field_num <= cur_field;
                    out_is_sync   <= 1'b1;

                    if (sym_cnt < 10'd4) begin
                        // 4 Segment sync symbols
                        out_symbol <= seg_sync_rom[sym_cnt[1:0]];
                    end else if (sym_cnt < 10'd515) begin
                        // 511 PN511 symbols (+5 or -5)
                        out_symbol <= pn511_lfsr[8] ? LVL_P5 : LVL_N5;
                        pn511_lfsr <= {pn511_lfsr[7:0], pn511_lfsr[8] ^ pn511_lfsr[6]};
                    end else if (sym_cnt < 10'd578) begin
                        // First PN63
                        out_symbol <= pn63_lfsr[5] ? LVL_P5 : LVL_N5;
                        pn63_lfsr  <= {pn63_lfsr[4:0], pn63_lfsr[5] ^ pn63_lfsr[4]};
                    end else if (sym_cnt < 10'd641) begin
                        // Middle PN63 (inverted in Field 2)
                        out_symbol <= (pn63_lfsr[5] ^ cur_field) ? LVL_P5 : LVL_N5;
                        pn63_lfsr  <= {pn63_lfsr[4:0], pn63_lfsr[5] ^ pn63_lfsr[4]};
                    end else if (sym_cnt < 10'd704) begin
                        // Third PN63
                        out_symbol <= pn63_lfsr[5] ? LVL_P5 : LVL_N5;
                        pn63_lfsr  <= {pn63_lfsr[4:0], pn63_lfsr[5] ^ pn63_lfsr[4]};
                    end else begin
                        // VSB mode & reserved symbols
                        out_symbol <= LVL_P5;
                    end

                    if (sym_cnt == 10'd831) begin
                        sym_cnt    <= 10'd0;
                        seg_cnt    <= 9'd1;
                        state      <= ST_SEG_SYNC;
                        pn511_lfsr <= 9'b100000000;
                        pn63_lfsr  <= 6'b100000;
                    end else begin
                        sym_cnt <= sym_cnt + 1'b1;
                    end
                end

                ST_SEG_SYNC: begin
                    // Emit 4 Segment Sync Symbols for Data Segment
                    out_valid     <= 1'b1;
                    out_symbol    <= seg_sync_rom[sym_cnt[1:0]];
                    out_sym_idx   <= sym_cnt;
                    out_seg_num   <= seg_cnt;
                    out_field_num <= cur_field;
                    out_is_sync   <= 1'b1;

                    if (sym_cnt == 10'd3) begin
                        sym_cnt <= 10'd4;
                        state   <= ST_DATA;
                    end else begin
                        sym_cnt <= sym_cnt + 1'b1;
                    end
                end

                ST_DATA: begin
                    // Transmit 828 Data Symbols from Trellis Encoder
                    if (in_valid) begin
                        out_valid     <= 1'b1;
                        out_symbol    <= in_symbol;
                        out_sym_idx   <= sym_cnt;
                        out_seg_num   <= seg_cnt;
                        out_field_num <= cur_field;
                        out_is_sync   <= 1'b0;

                        if (sym_cnt == 10'd831) begin
                            sym_cnt <= 10'd0;
                            if (seg_cnt == 9'd312) begin
                                // End of field: advance field number and transition to Field Sync
                                seg_cnt   <= 9'd0;
                                cur_field <= ~cur_field;
                                state     <= ST_FIELD_SYNC;
                            end else begin
                                seg_cnt <= seg_cnt + 1'b1;
                                state   <= ST_SEG_SYNC;
                            end
                        end else begin
                            sym_cnt <= sym_cnt + 1'b1;
                        end
                    end else begin
                        out_valid <= 1'b0;
                    end
                end
            endcase
        end
    end

endmodule
