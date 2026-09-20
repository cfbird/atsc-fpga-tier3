// ============================================================================
// Module: atsc_viterbi_decoder
// Target: Xilinx Spartan-6 XC6SLX150 (USRP B210)
// Description:
//   ATSC 12-Phase 8VSB Symbol Slicer and Trellis/Precoder Inverter.
//   1. Slices equalized soft symbol into 8 constellation levels {-7..+7} -> {Z2, Z1, Z0}.
//   2. Inverts 12-phase precoder: X1[n] = Z2[n] ^ Z2[n-1]
//   3. Inverts 12-phase convolutional encoder: X2[n] = Z1[n] ^ Z0[n-1]
//   4. Packs 4 dibits {X2, X1} into 1 codeword byte.
//   5. Emits 207 bytes per data segment (828 data symbols / 4 = 207 bytes).
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

    // 12 Phase Encoder state memory
    reg [11:0] prev_z2;
    reg [11:0] prev_z0;
    
    // Commutator counter (0 to 11)
    reg [3:0] phase_idx;
    
    // Dibit accumulation buffer
    reg [1:0] bit_accum_count;
    reg [7:0] current_byte;
    reg [7:0] byte_counter;
    
    // Slicing logic for 8VSB constellation
    reg z2, z1, z0;
    always @(*) begin
        if (in_soft_sym >= 16'sd3510)       begin z2 = 1'b1; z1 = 1'b1; z0 = 1'b1; end // +7
        else if (in_soft_sym >= 16'sd2340)  begin z2 = 1'b1; z1 = 1'b1; z0 = 1'b0; end // +5
        else if (in_soft_sym >= 16'sd1170)  begin z2 = 1'b1; z1 = 1'b0; z0 = 1'b1; end // +3
        else if (in_soft_sym >= 16'sd0)     begin z2 = 1'b1; z1 = 1'b0; z0 = 1'b0; end // +1
        else if (in_soft_sym >= -16'sd1170) begin z2 = 1'b0; z1 = 1'b1; z0 = 1'b1; end // -1
        else if (in_soft_sym >= -16'sd2340) begin z2 = 1'b0; z1 = 1'b1; z0 = 1'b0; end // -3
        else if (in_soft_sym >= -16'sd3510) begin z2 = 1'b0; z1 = 1'b0; z0 = 1'b1; end // -5
        else                                begin z2 = 1'b0; z1 = 1'b0; z0 = 1'b0; end // -7
    end

    wire x1 = z2 ^ prev_z2[phase_idx];
    wire x2 = z1 ^ prev_z0[phase_idx];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_z2           <= 12'd0;
            prev_z0           <= 12'd0;
            phase_idx         <= 4'd0;
            bit_accum_count   <= 2'd0;
            current_byte      <= 8'd0;
            byte_counter      <= 8'd0;
            out_byte_valid    <= 1'b0;
            out_codeword_byte <= 8'd0;
            out_byte_idx      <= 8'd0;
        end else if (in_valid && !in_is_field_sync && in_sym_idx >= 10'd4) begin
            // Update 12-phase state
            prev_z2[phase_idx] <= z2;
            prev_z0[phase_idx] <= z0;
            
            // Advance phase index (0 to 11)
            if (phase_idx >= 4'd11) phase_idx <= 4'd0;
            else phase_idx <= phase_idx + 1'b1;
            
            // Accumulate {x2, x1} into byte
            current_byte <= {current_byte[5:0], x2, x1};
            
            if (bit_accum_count == 2'd3) begin
                bit_accum_count   <= 2'd0;
                out_codeword_byte <= {current_byte[5:0], x2, x1};
                out_byte_idx      <= byte_counter;
                out_byte_valid    <= 1'b1;
                
                if (byte_counter >= 8'd206) byte_counter <= 8'd0;
                else byte_counter <= byte_counter + 8'd1;
            end else begin
                bit_accum_count <= bit_accum_count + 1'b1;
                out_byte_valid  <= 1'b0;
            end
        end else begin
            out_byte_valid <= 1'b0;
            if (in_valid && in_is_field_sync) begin
                phase_idx       <= 4'd0;
                bit_accum_count <= 2'd0;
                byte_counter    <= 8'd0;
            end
        end
    end

endmodule
