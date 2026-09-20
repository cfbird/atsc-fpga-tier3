// ============================================================================
// Module: atsc_tx_randomizer
// Standard: ATSC A/53 Part 2 (8VSB Terrestrial Broadcast)
// Target: Xilinx Spartan-6 XC6SLX150 (USRP B210)
// Description:
//   PRBS Data Scrambler / Randomizer for ATSC 8VSB Transmitter.
//   Polynomial: g(X) = X^14 + X^11 + 1
//   Preload: 0x018F at the beginning of each ATSC Field (every 312 data segments).
//   Sync byte (0x47) is stripped / not randomized; 187 payload bytes are randomized.
// ============================================================================

`timescale 1ns / 1ps
`include "atsc_constants.vh"

module atsc_tx_randomizer (
    input  wire        clk,
    input  wire        rst_n,
    
    // Input MPEG-TS Byte Stream (188-byte packets starting with 0x47)
    input  wire        in_valid,
    input  wire [7:0]  in_byte,
    input  wire        in_pkt_start,    // High on sync byte (0x47)
    input  wire        in_field_start,  // High on first segment of field
    
    // Output 187-byte Randomized Segment
    output reg         out_valid,
    output reg  [7:0]  out_byte,
    output reg  [7:0]  out_byte_idx,    // 0..186
    output reg         out_field_start,
    output reg         out_seg_start
);

    reg [13:0] lfsr;
    reg [7:0]  byte_cnt;
    reg        in_payload;

    // PRBS Next-Byte Combinatorial Generator
    function [7:0] prbs_next_byte;
        input [13:0] cur_lfsr;
        reg   [13:0] state;
        reg   [7:0]  pseudo_byte;
        reg          feedback;
        integer i;
        begin
            state = cur_lfsr;
            for (i = 0; i < 8; i = i + 1) begin
                feedback = state[13] ^ state[10];
                pseudo_byte[7-i] = state[13];
                state = {state[12:0], feedback};
            end
            prbs_next_byte = pseudo_byte;
        end
    endfunction

    // LFSR Next-State Function after 8 shifts
    function [13:0] lfsr_advance_8;
        input [13:0] cur_lfsr;
        reg   [13:0] state;
        reg          feedback;
        integer i;
        begin
            state = cur_lfsr;
            for (i = 0; i < 8; i = i + 1) begin
                feedback = state[13] ^ state[10];
                state = {state[12:0], feedback};
            end
            lfsr_advance_8 = state;
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lfsr            <= `ATSC_PRBS_PRELOAD;
            byte_cnt        <= 8'd0;
            out_valid       <= 1'b0;
            out_byte        <= 8'd0;
            out_byte_idx    <= 8'd0;
            out_field_start <= 1'b0;
            out_seg_start   <= 1'b0;
            in_payload      <= 1'b0;
        end else if (in_valid) begin
            if (in_pkt_start) begin
                // MPEG-TS 0x47 Sync byte received: reset segment byte index
                byte_cnt <= 8'd0;
                in_payload <= 1'b0;
                out_valid <= 1'b0;
                
                if (in_field_start) begin
                    lfsr <= `ATSC_PRBS_PRELOAD;
                end
            end else begin
                // 187 Payload bytes: XOR with PRBS
                out_valid       <= 1'b1;
                out_byte        <= in_byte ^ prbs_next_byte(lfsr);
                out_byte_idx    <= byte_cnt;
                out_seg_start   <= (byte_cnt == 8'd0);
                out_field_start <= in_field_start && (byte_cnt == 8'd0);
                
                lfsr            <= lfsr_advance_8(lfsr);
                byte_cnt        <= byte_cnt + 1'b1;
            end
        end else begin
            out_valid       <= 1'b0;
            out_field_start <= 1'b0;
            out_seg_start   <= 1'b0;
        end
    end

endmodule
