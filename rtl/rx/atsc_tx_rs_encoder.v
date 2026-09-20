// ============================================================================
// Module: atsc_tx_rs_encoder
// Standard: ATSC A/53 Part 2 (8VSB Terrestrial Broadcast)
// Target: Xilinx Spartan-6 XC6SLX150 (USRP B210)
// Description:
//   Reed-Solomon RS(207,187, t=10) Encoder over GF(2^8).
//   Generator polynomial: g(X) = (X + \alpha^0)(X + \alpha^1)...(X + \alpha^19)
//   Accepts 187 data bytes from randomizer and appends 20 parity bytes to make 207 bytes.
// ============================================================================

`timescale 1ns / 1ps
`include "atsc_constants.vh"

module atsc_tx_rs_encoder (
    input  wire        clk,
    input  wire        rst_n,
    
    // Input from Randomizer (187 bytes per segment)
    input  wire        in_valid,
    input  wire [7:0]  in_byte,
    input  wire [7:0]  in_byte_idx,
    input  wire        in_field_start,
    input  wire        in_seg_start,
    
    // Output 207-byte Codeword (187 data + 20 parity)
    output reg         out_valid,
    output reg  [7:0]  out_byte,
    output reg  [7:0]  out_byte_idx,    // 0..206
    output reg         out_field_start,
    output reg         out_seg_start
);

    // RS(207,187) Generator Polynomial Coefficients in GF(2^8) (alpha representation):
    // g(X) = g0 + g1*X + g2*X^2 + ... + g19*X^19 + X^20
    // Values derived from primitive polynomial p(X) = X^8 + X^4 + X^3 + X^2 + 1
    wire [7:0] g_coeff [0:19];
    assign g_coeff[0]  = 8'h2D;
    assign g_coeff[1]  = 8'h66;
    assign g_coeff[2]  = 8'h0E;
    assign g_coeff[3]  = 8'hB2;
    assign g_coeff[4]  = 8'h78;
    assign g_coeff[5]  = 8'h0F;
    assign g_coeff[6]  = 8'h9E;
    assign g_coeff[7]  = 8'hE8;
    assign g_coeff[8]  = 8'h6D;
    assign g_coeff[9]  = 8'h45;
    assign g_coeff[10] = 8'h70;
    assign g_coeff[11] = 8'h99;
    assign g_coeff[12] = 8'h65;
    assign g_coeff[13] = 8'h90;
    assign g_coeff[14] = 8'h1C;
    assign g_coeff[15] = 8'h20;
    assign g_coeff[16] = 8'hF2;
    assign g_coeff[17] = 8'h6F;
    assign g_coeff[18] = 8'h65;
    assign g_coeff[19] = 8'h5D;

    // GF(2^8) Galois Multiplication function
    function [7:0] gf_mult;
        input [7:0] a;
        input [7:0] b;
        reg [7:0] p;
        reg [7:0] a_run;
        integer i;
        begin
            p = 8'd0;
            a_run = a;
            for (i = 0; i < 8; i = i + 1) begin
                if (b[i]) p = p ^ a_run;
                if (a_run[7])
                    a_run = (a_run << 1) ^ 8'h1D; // Poly 0x11D without MSB
                else
                    a_run = a_run << 1;
            end
            gf_mult = p;
        end
    endfunction

    // 20-byte Parity Shift Register
    reg [7:0] parity [0:19];
    reg [7:0] state_cnt;
    reg       flushing_parity;
    reg       seg_start_latched;
    reg       field_start_latched;
    reg [7:0] feedback;

    integer k;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (k = 0; k < 20; k = k + 1) parity[k] <= 8'd0;
            state_cnt           <= 8'd0;
            flushing_parity     <= 1'b0;
            out_valid           <= 1'b0;
            out_byte            <= 8'd0;
            out_byte_idx        <= 8'd0;
            out_field_start     <= 1'b0;
            out_seg_start       <= 1'b0;
            seg_start_latched   <= 1'b0;
            field_start_latched <= 1'b0;
        end else begin
            if (in_valid && !flushing_parity) begin
                // Data phase (bytes 0..186)
                out_valid       <= 1'b1;
                out_byte        <= in_byte;
                out_byte_idx    <= in_byte_idx;
                out_seg_start   <= in_seg_start;
                out_field_start <= in_field_start;
                
                if (in_seg_start) begin
                    seg_start_latched   <= 1'b1;
                    field_start_latched <= in_field_start;
                end

                // Update RS Feedback Shift Register
                feedback = in_byte ^ parity[19];
                parity[0] <= gf_mult(feedback, g_coeff[0]);
                for (k = 1; k < 20; k = k + 1) begin
                    parity[k] <= parity[k-1] ^ gf_mult(feedback, g_coeff[k]);
                end

                if (in_byte_idx == 8'd186) begin
                    // Trigger parity emission for next 20 cycles
                    flushing_parity <= 1'b1;
                    state_cnt       <= 8'd0;
                end
            end else if (flushing_parity) begin
                // Parity emission phase (bytes 187..206)
                out_valid       <= 1'b1;
                out_byte        <= parity[19 - state_cnt];
                out_byte_idx    <= 8'd187 + state_cnt;
                out_seg_start   <= 1'b0;
                out_field_start <= 1'b0;
                
                if (state_cnt == 8'd19) begin
                    flushing_parity <= 1'b0;
                    state_cnt <= 8'd0;
                    // Reset parity shift registers for next segment
                    for (k = 0; k < 20; k = k + 1) parity[k] <= 8'd0;
                end else begin
                    state_cnt <= state_cnt + 1'b1;
                end
            end else begin
                out_valid       <= 1'b0;
                out_seg_start   <= 1'b0;
                out_field_start <= 1'b0;
            end
        end
    end

endmodule
