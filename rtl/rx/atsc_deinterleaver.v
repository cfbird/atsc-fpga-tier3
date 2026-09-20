// ============================================================================
// Module: atsc_deinterleaver
// Target: Xilinx Spartan-6 XC6SLX150 (USRP B210)
// Description:
//   ATSC 52-Branch Convolutional Byte Deinterleaver (B = 52, M = 4 bytes).
//   Branch j has delay (51 - j) * 4 bytes.
//   Implemented using Block RAM circular shift registers on FPGA.
// ============================================================================

`timescale 1ns / 1ps

module atsc_deinterleaver (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_byte_valid,
    input  wire [7:0]  in_byte,
    
    output reg         out_byte_valid,
    output reg  [7:0]  out_byte
);

    // Commutator index (0 to 51)
    reg [5:0] branch_idx;
    
    // Circular FIFO delay lines stored in Block RAM / distributed RAM
    // Total storage: sum_{j=0}^{51} (51-j)*4 = 51*52*2 = 5304 bytes
    reg [7:0] delay_mem [0:5303];
    reg [12:0] read_ptrs [0:51];
    reg [12:0] write_ptrs [0:51];
    
    integer b;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            branch_idx     <= 6'd0;
            out_byte_valid <= 1'b0;
            out_byte       <= 8'd0;
            for (b = 0; b < 52; b = b + 1) begin
                read_ptrs[b]  <= 13'd0;
                write_ptrs[b] <= 13'd0;
            end
        end else if (in_byte_valid) begin
            // Branch 51 has zero delay
            if (branch_idx == 6'd51) begin
                out_byte <= in_byte;
            end else begin
                // Read delayed byte from FIFO
                out_byte <= delay_mem[read_ptrs[branch_idx]];
                // Write new byte to FIFO
                delay_mem[write_ptrs[branch_idx]] <= in_byte;
                
                // Advance pointers modulo branch length
                write_ptrs[branch_idx] <= write_ptrs[branch_idx] + 1'b1;
                read_ptrs[branch_idx]  <= read_ptrs[branch_idx] + 1'b1;
            end
            
            out_byte_valid <= 1'b1;
            
            // Commutator update (0 to 51)
            if (branch_idx >= 6'd51) branch_idx <= 6'd0;
            else branch_idx <= branch_idx + 1'b1;
        end else begin
            out_byte_valid <= 1'b0;
        end
    end

endmodule
