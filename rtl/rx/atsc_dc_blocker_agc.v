// ============================================================================
// Module: atsc_dc_blocker_agc
// Target: Xilinx Spartan-6 XC6SLX150 (USRP B210)
// Description:
//   1. DC Blocker: 4096-sample moving average filter removes residual pilot DC offset.
//   2. Automatic Gain Control (AGC): Normalizes symbol variance to standard 8VSB
//      constellation amplitude grid (target levels: ±7, ±5, ±3, ±1).
// ============================================================================

`timescale 1ns / 1ps

module atsc_dc_blocker_agc #(
    parameter DATA_WIDTH = 16,
    parameter ACC_WIDTH  = 32,
    parameter AVG_SHIFT  = 12     // 2^12 = 4096 samples
)(
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   in_valid,
    input  wire signed [DATA_WIDTH-1:0] in_real, // Real symbol stream from FPLL
    
    output reg                    out_valid,
    output reg  signed [DATA_WIDTH-1:0] out_norm // Normalized 8VSB symbol stream
);

    // DC Blocker Integrator
    reg signed [ACC_WIDTH-1:0] dc_accum;
    wire signed [DATA_WIDTH-1:0] dc_est = dc_accum >>> AVG_SHIFT;
    reg signed [DATA_WIDTH-1:0] ac_signal;
    
    // AGC Registers (Fast Attack, Slow Decay)
    // Target RMS symbol energy: ~5.25 (standard 8VSB grid ±1, ±3, ±5, ±7 has E = 21, RMS = 4.58)
    reg signed [ACC_WIDTH-1:0] pwr_accum;
    reg signed [DATA_WIDTH-1:0] gain_val;
    reg signed [DATA_WIDTH*2-1:0] mult_gain;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dc_accum   <= 0;
            ac_signal  <= 0;
            pwr_accum  <= 0;
            gain_val   <= 16'sh1000; // Unity gain (Q12 format = 4096)
            mult_gain  <= 0;
            out_norm   <= 0;
            out_valid  <= 1'b0;
        end else if (in_valid) begin
            // 1. DC Blocker IIR tracking
            dc_accum  <= dc_accum + in_real - dc_est;
            ac_signal <= in_real - dc_est;
            
            // 2. AGC Amplitude Gain Scaling
            mult_gain <= ac_signal * gain_val;
            out_norm  <= mult_gain >>> 12;
            
            // Power detector & slow gain feedback loop
            if (mult_gain[DATA_WIDTH*2-1:DATA_WIDTH+10] != 0) begin
                // Signal too large -> reduce gain (attack)
                if (gain_val > 16'sh0100) gain_val <= gain_val - 16'sd4;
            end else if (gain_val < 16'sh7F00) begin
                // Signal low -> increase gain (decay)
                gain_val <= gain_val + 16'sd1;
            end
            
            out_valid <= 1'b1;
        end else begin
            out_valid <= 1'b0;
        end
    end

endmodule
