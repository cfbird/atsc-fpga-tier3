// ============================================================================
// Module: atsc_rrc_filter
// Target: Xilinx Spartan-6 XC6SLX150 (USRP B210)
// Description:
//   Root-Raised Cosine (RRC) matched filter (alpha = 0.1152).
//   Symmetric systolic architecture:
//   - I-Channel: High-speed hardware DSP48A1 multipliers
//   - Q-Channel: Logic slice LUT multipliers (Preserves DSP budget)
// ============================================================================

`timescale 1ns / 1ps

module atsc_rrc_filter #(
    parameter DATA_WIDTH = 16,
    parameter COEFF_WIDTH = 16,
    parameter NUM_TAPS   = 35
)(
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   in_valid,
    input  wire signed [DATA_WIDTH-1:0] in_i,
    input  wire signed [DATA_WIDTH-1:0] in_q,
    
    output reg                    out_valid,
    output reg  signed [DATA_WIDTH-1:0] out_i,
    output reg  signed [DATA_WIDTH-1:0] out_q
);

    // 18 unique symmetric coefficients for 35 taps (Q15 format)
    wire signed [COEFF_WIDTH-1:0] coeff [0:17];
    assign coeff[0]  = 16'sh0067; assign coeff[1]  = 16'sh01EA; assign coeff[2]  = 16'sh0346;
    assign coeff[3]  = 16'sh03AF; assign coeff[4]  = 16'sh025C; assign coeff[5]  = 16'shFEFE;
    assign coeff[6]  = 16'shFA40; assign coeff[7]  = 16'shF584; assign coeff[8]  = 16'shF383;
    assign coeff[9]  = 16'shF6F5; assign coeff[10] = 16'sh0152; assign coeff[11] = 16'sh1238;
    assign coeff[12] = 16'sh27B8; assign coeff[13] = 16'sh3F3A; assign coeff[14] = 16'sh54F0;
    assign coeff[15] = 16'sh65A2; assign coeff[16] = 16'sh6FF3; assign coeff[17] = 16'sh74E0;

    // Shift registers for I and Q samples (35 taps)
    reg signed [DATA_WIDTH-1:0] sr_i [0:NUM_TAPS-1];
    reg signed [DATA_WIDTH-1:0] sr_q [0:NUM_TAPS-1];
    
    // Accumulators for symmetric MAC pipeline
    (* use_dsp48 = "yes" *) reg signed [DATA_WIDTH+COEFF_WIDTH+5:0] acc_i;
    (* use_dsp48 = "no" *)  reg signed [DATA_WIDTH+COEFF_WIDTH+5:0] acc_q;
    
    integer k;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (k = 0; k < NUM_TAPS; k = k + 1) begin
                sr_i[k] <= {DATA_WIDTH{1'b0}};
                sr_q[k] <= {DATA_WIDTH{1'b0}};
            end
            out_i     <= 0;
            out_q     <= 0;
            out_valid <= 1'b0;
        end else if (in_valid) begin
            sr_i[0] <= in_i;
            sr_q[0] <= in_q;
            for (k = 1; k < NUM_TAPS; k = k + 1) begin
                sr_i[k] <= sr_i[k-1];
                sr_q[k] <= sr_q[k-1];
            end
            
            // Symmetric pre-add and multiply-accumulate
            acc_i = (sr_i[17] * coeff[17]); // Center tap
            acc_q = (sr_q[17] * coeff[17]);
            for (k = 0; k < 17; k = k + 1) begin
                acc_i = acc_i + (sr_i[k] + sr_i[NUM_TAPS-1-k]) * coeff[k];
                acc_q = acc_q + (sr_q[k] + sr_q[NUM_TAPS-1-k]) * coeff[k];
            end
            
            out_i     <= acc_i >>> 15;
            out_q     <= acc_q >>> 15;
            out_valid <= 1'b1;
        end else begin
            out_valid <= 1'b0;
        end
    end

endmodule
