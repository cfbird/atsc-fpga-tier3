// ============================================================================
// Module: atsc_deinterleaver
// Target: Xilinx Spartan-6 XC6SLX150 (USRP B210)
// Description:
//   ATSC 52-Branch Convolutional Byte Deinterleaver (B = 52, M = 4 bytes).
//   Branch j has delay (51 - j) * 4 bytes.
//   Total memory required: 52 * 51 / 2 * 4 = 5,304 bytes.
//   Synchronized to Field Sync (resets branch_idx to 0).
// ============================================================================

`timescale 1ns / 1ps

module atsc_deinterleaver (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_field_sync,
    input  wire        in_byte_valid,
    input  wire [7:0]  in_byte,
    
    output reg         out_byte_valid,
    output reg  [7:0]  out_byte
);

    // Commutator index (0 to 51)
    reg [5:0] branch_idx;
    
    // Circular FIFO delay lines stored in Block RAM (5304 bytes)
    reg [7:0] ram [0:5375];
    reg [12:0] ptrs [0:51];
    
    // Base offsets for 52 branches
    // Base[j] = sum_{k=0}^{j-1} (51 - k) * 4
    // Length[j] = (51 - j) * 4
    wire [12:0] base_offsets [0:51];
    wire [12:0] branch_len [0:51];
    
    genvar b;
    generate
        for (b = 0; b < 52; b = b + 1) begin : gen_deint_tables
            // sum_{k=0}^{b-1} (51 - k) * 4 = (51*b - b*(b-1)/2) * 4
            assign base_offsets[b] = (51 * b - (b * (b - 1)) / 2) * 4;
            assign branch_len[b]   = (51 - b) * 4;
        end
    endgenerate

    wire [12:0] addr = base_offsets[branch_idx] + ptrs[branch_idx];
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            branch_idx     <= 6'd0;
            out_byte_valid <= 1'b0;
            out_byte       <= 8'd0;
            for (i = 0; i < 52; i = i + 1) begin
                ptrs[i] <= 13'd0;
            end
        end else if (in_field_sync) begin
            branch_idx     <= 6'd0;
            out_byte_valid <= 1'b0;
        end else if (in_byte_valid) begin
            out_byte_valid <= 1'b1;
            
            if (branch_idx == 6'd51) begin
                // Branch 51 has zero delay
                out_byte <= in_byte;
            end else begin
                // Read delayed byte from FIFO and write new byte
                out_byte   <= ram[addr];
                ram[addr]  <= in_byte;
                
                if (ptrs[branch_idx] + 1'b1 >= branch_len[branch_idx])
                    ptrs[branch_idx] <= 13'd0;
                else
                    ptrs[branch_idx] <= ptrs[branch_idx] + 1'b1;
            end
            
            // Advance commutator (0 to 51)
            if (branch_idx >= 6'd51) branch_idx <= 6'd0;
            else branch_idx <= branch_idx + 1'b1;
        end else begin
            out_byte_valid <= 1'b0;
        end
    end

endmodule
