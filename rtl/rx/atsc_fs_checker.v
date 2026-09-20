// ============================================================================
// Module: atsc_fs_checker
// Target: Xilinx Spartan-6 XC6SLX150 (USRP B210)
// Description:
//   ATSC Field Sync and Data Segment Synchronizer & Framer.
//   1. Segment Sync Correlator (+5, -5, -5, +5) with Flywheel Lock Detector.
//   2. Fast-locking Search Mode with re-arming guard window.
//   3. Tracks 832-symbol segment boundaries and 313-segment field boundaries.
// ============================================================================

`timescale 1ns / 1ps

module atsc_fs_checker #(
    parameter DATA_WIDTH = 16
)(
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   in_sym_valid,
    input  wire signed [DATA_WIDTH-1:0] in_symbol,
    
    output reg                    out_seg_valid,   // High on every symbol
    output reg  signed [DATA_WIDTH-1:0] out_sym_data,
    output reg  [9:0]             out_sym_idx,     // 0 to 831 symbol index in segment
    output reg                    out_is_field_sync,// High during Field Sync segment
    output reg                    out_field_num    // 0 = Field 1, 1 = Field 2
);

    reg [9:0] sym_count;
    reg signed [DATA_WIDTH-1:0] history [0:3];
    reg signed [DATA_WIDTH+3:0] seg_sync_corr;
    reg [8:0] seg_count_in_field;
    
    reg [3:0] lock_conf;
    reg       is_locked;
    
    // Segment Sync Correlation threshold (Nominal peak ~20480 for ±5120 grid)
    localparam signed [DATA_WIDTH+3:0] CORR_THRESH = 18'sd8000;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sym_count          <= 10'd0;
            seg_count_in_field <= 9'd1; // Default to normal data segment upon reset
            lock_conf          <= 4'd0;
            is_locked          <= 1'b0;
            out_seg_valid      <= 1'b0;
            out_sym_data       <= 0;
            out_sym_idx        <= 10'd0;
            out_is_field_sync  <= 1'b0;
            out_field_num      <= 1'b0;
            history[0] <= 0; history[1] <= 0; history[2] <= 0; history[3] <= 0;
            seg_sync_corr <= 0;
        end else if (in_sym_valid) begin
            // Shift history buffer
            history[0] <= in_symbol;
            history[1] <= history[0];
            history[2] <= history[1];
            history[3] <= history[2];
            
            // Segment Sync Correlator (+5, -5, -5, +5)
            // history[3] was symbol 0 (+5)
            // history[2] was symbol 1 (-5)
            // history[1] was symbol 2 (-5)
            // history[0] is  symbol 3 (+5)
            seg_sync_corr <= (history[3] - history[2] - history[1] + history[0]);
            
            if (!is_locked) begin
                // Search Mode: trigger on correlation peak when armed (sym_count > 800 or == 0)
                if ((sym_count == 10'd0 || sym_count > 10'd800) && (seg_sync_corr > CORR_THRESH)) begin
                    sym_count <= 10'd3; // Symbol 3 just arrived
                    lock_conf <= lock_conf + 4'd1;
                    if (lock_conf >= 4'd2) begin
                        is_locked <= 1'b1;
                    end
                end else if (sym_count >= 10'd831) begin
                    sym_count <= 10'd0;
                    lock_conf <= 4'd0;
                    if (seg_count_in_field >= 9'd312) begin
                        seg_count_in_field <= 9'd0;
                        out_field_num <= ~out_field_num;
                    end else begin
                        seg_count_in_field <= seg_count_in_field + 9'd1;
                    end
                end else begin
                    sym_count <= sym_count + 10'd1;
                end
            end else begin
                // Flywheel Tracking Mode (Locked)
                if (sym_count >= 10'd831) begin
                    sym_count <= 10'd0;
                    if (seg_count_in_field >= 9'd312) begin
                        seg_count_in_field <= 9'd0;
                        out_field_num <= ~out_field_num;
                    end else begin
                        seg_count_in_field <= seg_count_in_field + 9'd1;
                    end
                end else begin
                    sym_count <= sym_count + 10'd1;
                    // Verify sync at symbol 3
                    if (sym_count == 10'd3) begin
                        if (seg_sync_corr > CORR_THRESH) begin
                            if (lock_conf < 4'd15) lock_conf <= lock_conf + 4'd1;
                        end else begin
                            if (lock_conf > 4'd0) lock_conf <= lock_conf - 4'd1;
                            else is_locked <= 1'b0; // Lost lock
                        end
                    end
                end
            end
            
            out_sym_idx       <= sym_count;
            out_sym_data      <= in_symbol;
            out_seg_valid     <= 1'b1;
            out_is_field_sync <= (seg_count_in_field == 9'd0);
            
        end else begin
            out_seg_valid <= 1'b0;
        end
    end

endmodule
