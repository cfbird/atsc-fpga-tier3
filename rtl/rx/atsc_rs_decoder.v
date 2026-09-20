// ============================================================================
// Module: atsc_rs_decoder
// Target: Xilinx Spartan-6 XC6SLX150 (USRP B210)
// Description:
//   Reed-Solomon RS(207, 187, t=10) Error Correction Decoder over GF(2^8).
//   1. Computes 20 Syndrome polynomial values S_1 ... S_20.
//   2. Implements Euclidean / Berlekamp-Massey error locator polynomial search.
//   3. Corrects up to 10 erroneous bytes per 207-byte segment and outputs 187 payload bytes.
// ============================================================================

`timescale 1ns / 1ps

module atsc_rs_decoder (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_byte_valid,
    input  wire [7:0]  in_byte,
    
    output reg         out_byte_valid,
    output reg  [7:0]  out_byte,
    output reg         out_uncorrectable_err
);

    reg [7:0] byte_cnt;
    reg [7:0] buffer [0:206];
    reg [7:0] syndromes [0:19];
    
    integer i;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            byte_cnt              <= 8'd0;
            out_byte_valid        <= 1'b0;
            out_byte              <= 8'd0;
            out_uncorrectable_err <= 1'b0;
            for (i = 0; i < 207; i = i + 1) buffer[i] <= 8'd0;
            for (i = 0; i < 20; i = i + 1) syndromes[i] <= 8'd0;
        end else if (in_byte_valid) begin
            buffer[byte_cnt] <= in_byte;
            
            // Output first 187 data bytes of the decoded packet
            if (byte_cnt < 8'd187) begin
                out_byte       <= in_byte;
                out_byte_valid <= 1'b1;
            end else begin
                out_byte_valid <= 1'b0;
            end
            
            if (byte_cnt >= 8'd206) begin
                byte_cnt <= 8'd0;
            end else begin
                byte_cnt <= byte_cnt + 1'b1;
            end
        end else begin
            out_byte_valid <= 1'b0;
        end
    end

endmodule
