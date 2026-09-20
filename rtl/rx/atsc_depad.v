// ============================================================================
// Module: atsc_depad
// Target: Xilinx Spartan-6 XC6SLX150 (USRP B210)
// Description:
//   MPEG Transport Stream Depadder & Sync Formatter.
//   Inserts standard MPEG-2 sync byte (0x47) at the beginning of each 187-byte
//   derandomized payload to output standard 188-byte MPEG-TS packets.
//   Uses an elastic 8-byte FIFO to ensure zero data byte loss.
// ============================================================================

`timescale 1ns / 1ps

module atsc_depad (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_byte_valid,
    input  wire [7:0]  in_byte,
    
    output reg         out_ts_valid,
    output reg  [7:0]  out_ts_byte,
    output reg         out_ts_sync_strobe // High on sync byte 0x47
);

    reg [7:0] in_byte_cnt;
    reg [7:0] out_byte_cnt;
    
    // Elastic FIFO (8 entries)
    reg [7:0] fifo_mem [0:7];
    reg [2:0] wr_ptr;
    reg [2:0] rd_ptr;
    reg [3:0] fifo_count;
    
    integer k;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            in_byte_cnt        <= 8'd0;
            out_byte_cnt       <= 8'd0;
            wr_ptr             <= 3'd0;
            rd_ptr             <= 3'd0;
            fifo_count         <= 4'd0;
            out_ts_valid       <= 1'b0;
            out_ts_byte        <= 8'd0;
            out_ts_sync_strobe <= 1'b0;
            for (k = 0; k < 8; k = k + 1) fifo_mem[k] <= 8'd0;
        end else begin
            // ----------------------------------------------------------------
            // FIFO Write & Read Control
            // ----------------------------------------------------------------
            if (in_byte_valid && (in_byte_cnt == 8'd0)) begin
                // New segment: push 0x47 AND the first data byte
                fifo_mem[wr_ptr] <= 8'h47;
                fifo_mem[(wr_ptr + 3'd1) & 3'd7] <= in_byte;
                wr_ptr <= (wr_ptr + 3'd2) & 3'd7;
                in_byte_cnt <= 8'd1;
                
                if (fifo_count > 4'd0) begin
                    // Simultaneous pop
                    out_ts_byte  <= fifo_mem[rd_ptr];
                    rd_ptr       <= (rd_ptr + 3'd1) & 3'd7;
                    out_ts_valid <= 1'b1;
                    fifo_count   <= fifo_count + 4'd1; // +2 - 1 = +1
                    
                    if (out_byte_cnt == 8'd0) begin
                        out_ts_sync_strobe <= 1'b1;
                        out_byte_cnt <= 8'd1;
                    end else begin
                        out_ts_sync_strobe <= 1'b0;
                        if (out_byte_cnt >= 8'd187) out_byte_cnt <= 8'd0;
                        else out_byte_cnt <= out_byte_cnt + 8'd1;
                    end
                end else begin
                    // No pop yet
                    out_ts_valid <= 1'b0;
                    out_ts_sync_strobe <= 1'b0;
                    fifo_count   <= fifo_count + 4'd2;
                end
                
            end else if (in_byte_valid) begin
                // Intermediate segment data byte
                fifo_mem[wr_ptr] <= in_byte;
                wr_ptr <= (wr_ptr + 3'd1) & 3'd7;
                
                if (in_byte_cnt >= 8'd186) in_byte_cnt <= 8'd0;
                else in_byte_cnt <= in_byte_cnt + 8'd1;
                
                if (fifo_count > 4'd0) begin
                    // Simultaneous pop
                    out_ts_byte  <= fifo_mem[rd_ptr];
                    rd_ptr       <= (rd_ptr + 3'd1) & 3'd7;
                    out_ts_valid <= 1'b1;
                    fifo_count   <= fifo_count; // +1 - 1 = 0
                    
                    if (out_byte_cnt == 8'd0) begin
                        out_ts_sync_strobe <= 1'b1;
                        out_byte_cnt <= 8'd1;
                    end else begin
                        out_ts_sync_strobe <= 1'b0;
                        if (out_byte_cnt >= 8'd187) out_byte_cnt <= 8'd0;
                        else out_byte_cnt <= out_byte_cnt + 8'd1;
                    end
                end else begin
                    out_ts_valid <= 1'b0;
                    out_ts_sync_strobe <= 1'b0;
                    fifo_count   <= fifo_count + 4'd1;
                end
                
            end else if (fifo_count > 4'd0) begin
                // Drain FIFO when in_byte_valid is low
                out_ts_byte  <= fifo_mem[rd_ptr];
                rd_ptr       <= (rd_ptr + 3'd1) & 3'd7;
                fifo_count   <= fifo_count - 4'd1;
                out_ts_valid <= 1'b1;
                
                if (out_byte_cnt == 8'd0) begin
                    out_ts_sync_strobe <= 1'b1;
                    out_byte_cnt <= 8'd1;
                end else begin
                    out_ts_sync_strobe <= 1'b0;
                    if (out_byte_cnt >= 8'd187) out_byte_cnt <= 8'd0;
                    else out_byte_cnt <= out_byte_cnt + 8'd1;
                end
            end else begin
                out_ts_valid       <= 1'b0;
                out_ts_sync_strobe <= 1'b0;
            end
        end
    end

endmodule
