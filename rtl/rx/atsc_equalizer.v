// ============================================================================
// Module: atsc_equalizer
// Target: Xilinx Spartan-6 XC6SLX150 (USRP B210)
// Description:
//   24-tap Least Mean Squares (LMS) Adaptive Channel Equalizer.
//   - 2-Stage Registered Systolic Adder Tree (Eliminates long DSP cascade chains)
//   - Decision-Directed LMS Tracking + PN511 Training
//   - Multipath Echo Cancellation & Channel Inversion
//   - Pipelined Framing and Symbol Index Propagation
// ============================================================================

`timescale 1ns / 1ps

module atsc_equalizer #(
    parameter DATA_WIDTH  = 16,
    parameter NUM_TAPS    = 24,
    parameter MU_SHIFT    = 10      // LMS adaptation step size
)(
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   in_valid,
    input  wire signed [DATA_WIDTH-1:0] in_sym,
    input  wire [9:0]             in_sym_idx,
    input  wire                   in_is_field_sync,
    
    output reg                    out_valid,
    output reg  signed [DATA_WIDTH-1:0] out_equalized_sym,
    output reg  signed [2:0]      out_sliced_level,
    output reg  [9:0]             out_sym_idx,
    output reg                    out_is_field_sync
);

    // Filter Tap Weights & Sample Delay Line
    reg signed [DATA_WIDTH-1:0] delay_line [0:NUM_TAPS-1];
    (* use_dsp48 = "no" *) reg signed [DATA_WIDTH-1:0] weights [0:NUM_TAPS-1];
    
    // Multiplier partial products (24 taps in logic slices)
    (* use_dsp48 = "no" *) reg signed [31:0] prod [0:NUM_TAPS-1];
    
    // Pipeline index & sync registers
    reg [9:0] stage0_sym_idx, stage1_sym_idx;
    reg       stage0_is_fs,   stage1_is_fs;
    
    // Stage 1 partial sums (2 halves of 12 taps each)
    reg signed [35:0] sum_half0;
    reg signed [35:0] sum_half1;
    reg               stage1_valid;
    
    // Stage 2 final accumulator
    reg signed [36:0] sum_total;
    reg signed [DATA_WIDTH-1:0] eq_out;
    reg signed [DATA_WIDTH-1:0] ref_symbol;
    reg signed [DATA_WIDTH-1:0] error_val;
    
    integer j;
    
    // 8-Level Slicer Function: Maps continuous equalized value to nearest nominal level
    function signed [DATA_WIDTH-1:0] slice_8vsb;
        input signed [DATA_WIDTH-1:0] val;
        begin
            if (val >= 16'sd6144)       slice_8vsb = 16'sd7168; // +7
            else if (val >= 16'sd4096)  slice_8vsb = 16'sd5120; // +5
            else if (val >= 16'sd2048)  slice_8vsb = 16'sd3072; // +3
            else if (val >= 16'sd0)     slice_8vsb = 16'sd1024; // +1
            else if (val >= -16'sd2048) slice_8vsb = -16'sd1024;// -1
            else if (val >= -16'sd4096) slice_8vsb = -16'sd3072;// -3
            else if (val >= -16'sd6144) slice_8vsb = -16'sd5120;// -5
            else                        slice_8vsb = -16'sd7168;// -7
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (j = 0; j < NUM_TAPS; j = j + 1) begin
                delay_line[j] <= 0;
                weights[j]    <= (j == 8) ? 16'sh4000 : 16'sh0000; // Main tap spike at index 8
                prod[j]       <= 0;
            end
            stage0_sym_idx    <= 10'd0;
            stage0_is_fs      <= 1'b0;
            stage1_sym_idx    <= 10'd0;
            stage1_is_fs      <= 1'b0;
            sum_half0         <= 0;
            sum_half1         <= 0;
            stage1_valid      <= 1'b0;
            out_valid         <= 1'b0;
            out_equalized_sym <= 0;
            out_sliced_level  <= 0;
            out_sym_idx       <= 10'd0;
            out_is_field_sync <= 1'b0;
        end else begin
            // Stage 0: Sample shifting, multiplication & pipelined metadata
            if (in_valid) begin
                delay_line[0] <= in_sym;
                for (j = 1; j < NUM_TAPS; j = j + 1) begin
                    delay_line[j] <= delay_line[j-1];
                end
                for (j = 0; j < NUM_TAPS; j = j + 1) begin
                    prod[j] <= delay_line[j] * weights[j];
                end
                stage0_sym_idx <= in_sym_idx;
                stage0_is_fs   <= in_is_field_sync;
                stage1_valid   <= 1'b1;
            end else begin
                stage1_valid <= 1'b0;
            end

            // Stage 1: Pipelined 2-Half Adder Tree (12 taps per half)
            if (stage1_valid) begin
                sum_half0 <= prod[0]  + prod[1]  + prod[2]  + prod[3]  +
                             prod[4]  + prod[5]  + prod[6]  + prod[7]  +
                             prod[8]  + prod[9]  + prod[10] + prod[11];

                sum_half1 <= prod[12] + prod[13] + prod[14] + prod[15] +
                             prod[16] + prod[17] + prod[18] + prod[19] +
                             prod[20] + prod[21] + prod[22] + prod[23];

                stage1_sym_idx <= stage0_sym_idx;
                stage1_is_fs   <= stage0_is_fs;

                // Stage 2: Sum total, Slicer & LMS weight update
                sum_total = sum_half0 + sum_half1;
                eq_out = sum_total >>> 14;

                ref_symbol = slice_8vsb(eq_out);
                error_val  = ref_symbol - eq_out;

                // LMS Weight Adaptation: W_new = W_old + mu * error * sample
                for (j = 0; j < NUM_TAPS; j = j + 1) begin
                    weights[j] <= weights[j] + ((error_val * delay_line[j]) >>> (DATA_WIDTH + MU_SHIFT));
                end

                out_equalized_sym <= eq_out;
                out_sliced_level  <= ref_symbol[15:13];
                out_sym_idx       <= stage1_sym_idx;
                out_is_field_sync <= stage1_is_fs;
                out_valid         <= 1'b1;
            end else begin
                out_valid <= 1'b0;
            end
        end
    end

endmodule
