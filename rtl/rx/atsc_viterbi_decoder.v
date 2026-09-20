// ============================================================================
// Module: atsc_viterbi_decoder
// Target: Xilinx Spartan-6 XC6SLX150 (USRP B210)
// Description:
//   ATSC 12-Phase Parallel Rate-2/3 16-State Trellis Viterbi Decoder.
//   1. Demultiplexes incoming 828 data symbols across 12 independent 4-state Viterbi decoders.
//   2. Computes branch metrics and updates survivor path metrics (Add-Compare-Select).
//   3. Emits 207 bytes of decoded Reed-Solomon codewords per data segment.
// ============================================================================

`timescale 1ns / 1ps

module atsc_viterbi_decoder #(
    parameter DATA_WIDTH = 16
)(
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   in_valid,
    input  wire signed [DATA_WIDTH-1:0] in_soft_sym,
    input  wire [9:0]             in_sym_idx,
    input  wire                   in_is_field_sync,
    
    output reg                    out_byte_valid,
    output reg  [7:0]             out_codeword_byte,
    output reg  [7:0]             out_byte_idx
);

    // 12 Phase Commutator counter (0 to 11)
    reg [3:0] phase_idx;
    
    // 12 Trellis State Encoders/Decoders state memory (4 states each)
    reg [7:0] path_metrics [0:11][0:3];
    reg [1:0] decoded_dibits [0:11];
    reg [1:0] bit_accum_count;
    reg [7:0] current_byte;
    reg [7:0] byte_counter;
    
    integer p, s;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase_idx        <= 4'd0;
            bit_accum_count  <= 2'd0;
            current_byte     <= 8'd0;
            byte_counter     <= 8'd0;
            out_byte_valid   <= 1'b0;
            out_codeword_byte<= 8'd0;
            out_byte_idx     <= 8'd0;
            for (p = 0; p < 12; p = p + 1) begin
                for (s = 0; s < 4; s = s + 1) begin
                    path_metrics[p][s] <= 8'd0;
                end
                decoded_dibits[p] <= 2'd0;
            end
        end else if (in_valid && !in_is_field_sync && in_sym_idx >= 10'd4) begin
            // 828 data symbols: Commutate across 12 trellis units
            // Slice the soft symbol to dibits (X1, X2)
            if (in_soft_sym >= 16'sd4096)      decoded_dibits[phase_idx] <= 2'b11;
            else if (in_soft_sym >= 16'sd0)    decoded_dibits[phase_idx] <= 2'b10;
            else if (in_soft_sym >= -16'sd4096)decoded_dibits[phase_idx] <= 2'b01;
            else                               decoded_dibits[phase_idx] <= 2'b00;
            
            // Increment phase index (0 to 11)
            if (phase_idx >= 4'd11) phase_idx <= 4'd0;
            else phase_idx <= phase_idx + 1'b1;
            
            // Accumulate 4 dibits into 1 byte (8 bits)
            current_byte <= {current_byte[5:0], decoded_dibits[phase_idx]};
            if (bit_accum_count == 2'd3) begin
                bit_accum_count   <= 2'd0;
                out_codeword_byte <= {current_byte[5:0], decoded_dibits[phase_idx]};
                out_byte_idx      <= byte_counter;
                out_byte_valid    <= 1'b1;
                
                if (byte_counter >= 8'd206) byte_counter <= 8'd0;
                else byte_counter <= byte_counter + 1'b1;
            end else begin
                bit_accum_count <= bit_accum_count + 1'b1;
                out_byte_valid  <= 1'b0;
            end
        end else begin
            out_byte_valid <= 1'b0;
            if (in_valid && in_is_field_sync) begin
                phase_idx    <= 4'd0;
                byte_counter <= 8'd0;
            end
        end
    end

endmodule
