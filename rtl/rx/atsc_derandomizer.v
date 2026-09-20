// ============================================================================
// Module: atsc_derandomizer
// Target: Xilinx Spartan-6 XC6SLX150 (USRP B210)
// Description:
//   ATSC MPEG-2 PRBS Derandomizer.
//   1. Generates pseudo-random binary sequence using Galois LFSR g(X) = X^14 + X^11 + 1.
//   2. XORs incoming 187 payload bytes to recover raw MPEG-2 transport stream data.
//   3. Preloads with 0x018F at the start of each Data Field.
// ============================================================================

`timescale 1ns / 1ps

module atsc_derandomizer (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_field_sync_strobe,
    input  wire        in_byte_valid,
    input  wire [7:0]  in_byte,
    
    output reg         out_byte_valid,
    output reg  [7:0]  out_byte
);

    reg [13:0] lfsr;
    reg [7:0] prbs_byte;
    integer k;
    
    // Compute 8 PRBS bits per clock cycle
    always @(*) begin
        prbs_byte = 8'd0;
        // Combinatorial LFSR shift of 8 bits
        prbs_byte[7] = lfsr[13] ^ lfsr[10];
        prbs_byte[6] = lfsr[12] ^ lfsr[9];
        prbs_byte[5] = lfsr[11] ^ lfsr[8];
        prbs_byte[4] = lfsr[10] ^ lfsr[7];
        prbs_byte[3] = lfsr[9]  ^ lfsr[6];
        prbs_byte[2] = lfsr[8]  ^ lfsr[5];
        prbs_byte[1] = lfsr[7]  ^ lfsr[4];
        prbs_byte[0] = lfsr[6]  ^ lfsr[3];
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lfsr           <= 14'h018F;
            out_byte_valid <= 1'b0;
            out_byte       <= 8'd0;
        end else if (in_field_sync_strobe) begin
            // Re-seed PRBS generator on Field Sync
            lfsr           <= 14'h018F;
            out_byte_valid <= 1'b0;
        end else if (in_byte_valid) begin
            // XOR payload byte with PRBS sequence
            out_byte       <= in_byte ^ prbs_byte;
            out_byte_valid <= 1'b1;
            
            // Advance LFSR by 8 states
            lfsr <= {lfsr[5:0], prbs_byte};
        end else begin
            out_byte_valid <= 1'b0;
        end
    end

endmodule
