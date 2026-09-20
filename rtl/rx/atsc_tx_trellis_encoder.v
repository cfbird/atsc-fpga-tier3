// ============================================================================
// Module: atsc_tx_trellis_encoder
// Standard: ATSC A/53 Part 2 (8VSB Terrestrial Broadcast)
// Target: Xilinx Spartan-6 XC6SLX150 (USRP B210)
// Description:
//   12-Phase Parallel Rate-2/3 Trellis Coder and 8VSB Constellation Mapper.
//   Takes 207 bytes per segment, unpacks into 828 2-bit pairs (X1, X2),
//   encodes across 12 independent Trellis encoders, and outputs 828 8VSB symbols
//   mapped to levels in {-7, -5, -3, -1, +1, +3, +5, +7}.
// ============================================================================

`timescale 1ns / 1ps
`include "atsc_constants.vh"

module atsc_tx_trellis_encoder #(
    parameter DATA_WIDTH = 16
)(
    input  wire        clk,
    input  wire        rst_n,
    
    // Input Interleaved Bytes (207 bytes / segment)
    input  wire        in_valid,
    input  wire [7:0]  in_byte,
    input  wire [7:0]  in_byte_idx,
    input  wire        in_field_start,
    input  wire        in_seg_start,
    
    // Output 8VSB Sliced Symbols (828 data symbols per segment)
    output reg         out_valid,
    output reg  signed [DATA_WIDTH-1:0] out_symbol,
    output reg  [9:0]  out_sym_idx,     // 0..827
    output reg         out_field_start,
    output reg         out_seg_start
);

    // 12 Parallel Trellis Encoders State Registers
    // Each encoder has: precoder state P1, conv encoder state D1, D2
    reg [11:0] precoder_state;
    reg [11:0] conv_d1_state;
    reg [11:0] conv_d2_state;

    // Unpacking FIFO / shift buffer for 4 pairs of 2-bit symbols from each incoming byte
    reg [7:0]  byte_holding;
    reg [1:0]  pair_idx;
    reg        busy_unpacking;
    reg [3:0]  encoder_sel;
    reg [9:0]  symbol_counter;
    reg        field_start_reg;
    reg        seg_start_reg;

    // 8VSB Constellation Level Mapping ROM
    // 3'b000 -> -7, 3'b001 -> -5, 3'b010 -> -3, 3'b011 -> -1
    // 3'b100 -> +1, 3'b101 -> +3, 3'b110 -> +5, 3'b111 -> +7
    // Scaled to 16-bit Q12 fixed-point format: 1 unit = 4096 / 7 = ~585
    localparam signed [DATA_WIDTH-1:0] LVL_N7 = -16'sd4095;
    localparam signed [DATA_WIDTH-1:0] LVL_N5 = -16'sd2925;
    localparam signed [DATA_WIDTH-1:0] LVL_N3 = -16'sd1755;
    localparam signed [DATA_WIDTH-1:0] LVL_N1 = -16'sd585;
    localparam signed [DATA_WIDTH-1:0] LVL_P1 =  16'sd585;
    localparam signed [DATA_WIDTH-1:0] LVL_P3 =  16'sd1755;
    localparam signed [DATA_WIDTH-1:0] LVL_P5 =  16'sd2925;
    localparam signed [DATA_WIDTH-1:0] LVL_P7 =  16'sd4095;

    function signed [DATA_WIDTH-1:0] map_3bit_to_level;
        input [2:0] code;
        case (code)
            3'b000: map_3bit_to_level = LVL_N7;
            3'b001: map_3bit_to_level = LVL_N5;
            3'b010: map_3bit_to_level = LVL_N3;
            3'b011: map_3bit_to_level = LVL_N1;
            3'b100: map_3bit_to_level = LVL_P1;
            3'b101: map_3bit_to_level = LVL_P3;
            3'b110: map_3bit_to_level = LVL_P5;
            3'b111: map_3bit_to_level = LVL_P7;
        endcase
    endfunction

    reg x1, x2;
    reg z2, z1, z0;
    reg [3:0] idx;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            precoder_state  <= 12'd0;
            conv_d1_state   <= 12'd0;
            conv_d2_state   <= 12'd0;
            byte_holding    <= 8'd0;
            pair_idx        <= 2'd0;
            busy_unpacking  <= 1'b0;
            encoder_sel     <= 4'd0;
            symbol_counter  <= 10'd0;
            out_valid       <= 1'b0;
            out_symbol      <= 16'sd0;
            out_sym_idx     <= 10'd0;
            out_field_start <= 1'b0;
            out_seg_start   <= 1'b0;
            field_start_reg <= 1'b0;
            seg_start_reg   <= 1'b0;
        end else begin
            if (in_valid && !busy_unpacking) begin
                byte_holding    <= in_byte;
                busy_unpacking  <= 1'b1;
                pair_idx        <= 2'd0;
                field_start_reg <= in_field_start;
                seg_start_reg   <= in_seg_start;
            end
            
            if (busy_unpacking) begin
                // Extract 2-bit symbol: X2 (MSB), X1 (LSB)
                idx = encoder_sel;
                
                case (pair_idx)
                    2'd0: {x2, x1} = byte_holding[7:6];
                    2'd1: {x2, x1} = byte_holding[5:4];
                    2'd2: {x2, x1} = byte_holding[3:2];
                    2'd3: {x2, x1} = byte_holding[1:0];
                endcase

                // 1. Precoder for X1: Z2[n] = X1[n] ^ Z2[n-1]
                z2 = x1 ^ precoder_state[idx];
                precoder_state[idx] <= z2;

                // 2. Convolutional Encoder for X2:
                // Z1[n] = X2[n] ^ D2[n-1]
                // Z0[n] = D1[n-1]
                z1 = x2 ^ conv_d2_state[idx];
                z0 = conv_d1_state[idx];
                
                conv_d2_state[idx] <= conv_d1_state[idx];
                conv_d1_state[idx] <= x2;

                // 3. Map {z2, z1, z0} to 8VSB constellation level
                out_valid       <= 1'b1;
                out_symbol      <= map_3bit_to_level({z2, z1, z0});
                out_sym_idx     <= symbol_counter;
                out_seg_start   <= (symbol_counter == 10'd0);
                out_field_start <= field_start_reg && (symbol_counter == 10'd0);

                // Advance symbol counter (0..827)
                if (symbol_counter == 10'd827)
                    symbol_counter <= 10'd0;
                else
                    symbol_counter <= symbol_counter + 1'b1;

                // Advance 12-phase encoder selection
                if (encoder_sel == 4'd11)
                    encoder_sel <= 4'd0;
                else
                    encoder_sel <= encoder_sel + 1'b1;

                // Advance 2-bit pair index within byte
                if (pair_idx == 2'd3) begin
                    busy_unpacking <= 1'b0;
                    pair_idx <= 2'd0;
                end else begin
                    pair_idx <= pair_idx + 1'b1;
                end
            end else begin
                out_valid       <= 1'b0;
                out_seg_start   <= 1'b0;
                out_field_start <= 1'b0;
            end
        end
    end

endmodule
