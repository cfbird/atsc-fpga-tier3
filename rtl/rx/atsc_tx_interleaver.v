// ============================================================================
// Module: atsc_tx_interleaver
// Standard: ATSC A/53 Part 2 (8VSB Terrestrial Broadcast)
// Target: Xilinx Spartan-6 XC6SLX150 (USRP B210)
// Description:
//   52-Branch Convolutional Byte Interleaver with branch delay j * M (M = 4 bytes).
//   Branch 0: 0 delay, Branch 51: 204 bytes delay.
//   Total memory required: 52 * 51 / 2 * 4 = 5,304 bytes (utilizes 3 Spartan-6 18Kb BRAMs).
// ============================================================================

`timescale 1ns / 1ps
`include "atsc_constants.vh"

module atsc_tx_interleaver (
    input  wire        clk,
    input  wire        rst_n,
    
    // Input 207-byte Codewords from RS Encoder
    input  wire        in_valid,
    input  wire [7:0]  in_byte,
    input  wire [7:0]  in_byte_idx,
    input  wire        in_field_start,
    input  wire        in_seg_start,
    
    // Output Interleaved 207-byte Stream
    output reg         out_valid,
    output reg  [7:0]  out_byte,
    output reg  [7:0]  out_byte_idx,
    output reg         out_field_start,
    output reg         out_seg_start
);

    // Branch selection index (0..51)
    reg [5:0] branch_idx;
    
    // Interleaver RAM for 52 branches: Total depth 5304 bytes
    // Branch j has depth j * 4 bytes
    reg [7:0] ram [0:5375];
    reg [12:0] read_ptrs [0:51];
    reg [12:0] write_ptrs [0:51];
    
    // Branch base offsets in RAM
    wire [12:0] base_offsets [0:51];
    genvar b;
    generate
        for (b = 0; b < 52; b = b + 1) begin : gen_base
            assign base_offsets[b] = (b * (b - 1) / 2) * 4;
        end
    endgenerate

    wire [12:0] branch_len = {5'b0, branch_idx, 2'b00};
    wire [12:0] r_addr = base_offsets[branch_idx] + read_ptrs[branch_idx];
    wire [12:0] w_addr = base_offsets[branch_idx] + write_ptrs[branch_idx];

    reg [7:0] seg_byte_cnt;
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            branch_idx      <= 6'd0;
            seg_byte_cnt    <= 8'd0;
            out_valid       <= 1'b0;
            out_byte        <= 8'd0;
            out_byte_idx    <= 8'd0;
            out_field_start <= 1'b0;
            out_seg_start   <= 1'b0;
            for (i = 0; i < 52; i = i + 1) begin
                read_ptrs[i]  <= 13'd0;
                write_ptrs[i] <= 13'd0;
            end
        end else if (in_valid) begin
            out_valid       <= 1'b1;
            out_byte_idx    <= seg_byte_cnt;
            out_seg_start   <= (seg_byte_cnt == 8'd0);
            out_field_start <= in_field_start && (seg_byte_cnt == 8'd0);
            
            if (branch_idx == 6'd0) begin
                // Branch 0: Zero delay
                out_byte <= in_byte;
            end else begin
                // Branch j: FIFO delay of j * 4 bytes
                out_byte <= ram[r_addr];
                ram[w_addr] <= in_byte;
                
                // Advance FIFO pointers for this branch
                if (read_ptrs[branch_idx] + 1'b1 >= branch_len)
                    read_ptrs[branch_idx] <= 13'd0;
                else
                    read_ptrs[branch_idx] <= read_ptrs[branch_idx] + 1'b1;
                    
                if (write_ptrs[branch_idx] + 1'b1 >= branch_len)
                    write_ptrs[branch_idx] <= 13'd0;
                else
                    write_ptrs[branch_idx] <= write_ptrs[branch_idx] + 1'b1;
            end
            
            // Advance branch counter (modulo 52)
            if (branch_idx == 6'd51)
                branch_idx <= 6'd0;
            else
                branch_idx <= branch_idx + 1'b1;
                
            // Advance segment byte counter (0..206)
            if (seg_byte_cnt == 8'd206)
                seg_byte_cnt <= 8'd0;
            else
                seg_byte_cnt <= seg_byte_cnt + 1'b1;
                
        end else begin
            out_valid       <= 1'b0;
            out_seg_start   <= 1'b0;
            out_field_start <= 1'b0;
        end
    end

endmodule
