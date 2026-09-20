// ============================================================================
// Module: atsc_tx_pilot_adder
// Standard: ATSC A/53 Part 2 (8VSB Terrestrial Broadcast)
// Target: Xilinx Spartan-6 XC6SLX150 (USRP B210)
// Description:
//   ATSC DC Pilot Offset Adder.
//   Adds a nominal DC bias of +1.25 units to the 8-level symbols
//   ({-7, -5, -3, -1, +1, +3, +5, +7} -> {-5.75, -3.75, -1.75, +0.25, +2.25, +4.25, +6.25, +8.25}).
//   In Q12 format (1 unit = 585): DC offset = 1.25 * 585 = +731.
// ============================================================================

`timescale 1ns / 1ps
`include "atsc_constants.vh"

module atsc_tx_pilot_adder #(
    parameter DATA_WIDTH = 16
)(
    input  wire        clk,
    input  wire        rst_n,
    
    // Input 8VSB Symbols from Sync Mux
    input  wire        in_valid,
    input  wire signed [DATA_WIDTH-1:0] in_symbol,
    input  wire [9:0]  in_sym_idx,
    input  wire [8:0]  in_seg_num,
    input  wire        in_field_num,
    input  wire        in_is_sync,
    
    // Output Pilot-Injected Symbols
    output reg         out_valid,
    output reg  signed [DATA_WIDTH-1:0] out_symbol,
    output reg  [9:0]  out_sym_idx,
    output reg  [8:0]  out_seg_num,
    output reg         out_field_num,
    output reg         out_is_sync
);

    // +1.25 DC Pilot in Q12 fixed point format
    localparam signed [DATA_WIDTH-1:0] PILOT_OFFSET = 16'sd731;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid     <= 1'b0;
            out_symbol    <= 16'sd0;
            out_sym_idx   <= 10'd0;
            out_seg_num   <= 9'd0;
            out_field_num <= 1'b0;
            out_is_sync   <= 1'b0;
        end else if (in_valid) begin
            out_valid     <= 1'b1;
            out_symbol    <= in_symbol + PILOT_OFFSET;
            out_sym_idx   <= in_sym_idx;
            out_seg_num   <= in_seg_num;
            out_field_num <= in_field_num;
            out_is_sync   <= in_is_sync;
        end else begin
            out_valid <= 1'b0;
        end
    end

endmodule
