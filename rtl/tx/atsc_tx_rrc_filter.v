// ============================================================================
// Module: atsc_tx_rrc_filter
// Standard: ATSC A/53 Part 2 (8VSB Terrestrial Broadcast)
// Target: Xilinx Spartan-6 XC6SLX150 (USRP B210)
// Description:
//   Complex 8VSB Pulse Shaping Filter (RRC In-Phase + Hilbert Quadrature).
//   - Alpha: 0.1152
//   - Taps: 31-tap symmetric systolic FIR
//   - Produces Complex I/Q Baseband samples ready for AD9361 TX DAC.
// ============================================================================

`timescale 1ns / 1ps
`include "atsc_constants.vh"

module atsc_tx_rrc_filter #(
    parameter DATA_WIDTH = 16,
    parameter NUM_TAPS   = 31
)(
    input  wire                   clk,
    input  wire                   rst_n,
    
    // Real Pilot-Injected Symbols at ATSC Symbol Rate (~10.76 MSps)
    input  wire                   in_valid,
    input  wire signed [DATA_WIDTH-1:0] in_symbol,
    
    // Complex 8VSB Baseband Output (I/Q)
    output reg                    out_valid,
    output reg  signed [DATA_WIDTH-1:0] out_i,
    output reg  signed [DATA_WIDTH-1:0] out_q
);

    // 31-Tap RRC (In-Phase) Coefficients (Q15 Fixed-Point):
    wire signed [15:0] h_i [0:30];
    assign h_i[0]  = 16'sd12;   assign h_i[1]  = -16'sd18;  assign h_i[2]  = -16'sd42;
    assign h_i[3]  = 16'sd35;   assign h_i[4]  = 16'sd98;   assign h_i[5]  = -16'sd45;
    assign h_i[6]  = -16'sd185; assign h_i[7]  = 16'sd30;   assign h_i[8]  = 16'sd320;
    assign h_i[9]  = 16'sd20;   assign h_i[10] = -16'sd560; assign h_i[11] = -16'sd210;
    assign h_i[12] = 16'sd1120; assign h_i[13] = 16'sd3450; assign h_i[14] = 16'sd6200;
    assign h_i[15] = 16'sd7500; // Center peak tap
    assign h_i[16] = 16'sd6200; assign h_i[17] = 16'sd3450; assign h_i[18] = 16'sd1120;
    assign h_i[19] = -16'sd210; assign h_i[20] = -16'sd560; assign h_i[21] = 16'sd20;
    assign h_i[22] = 16'sd320;  assign h_i[23] = 16'sd30;   assign h_i[24] = -16'sd185;
    assign h_i[25] = -16'sd45;  assign h_i[26] = 16'sd98;   assign h_i[27] = 16'sd35;
    assign h_i[28] = -16'sd42;  assign h_i[29] = -16'sd18;  assign h_i[30] = 16'sd12;

    // 31-Tap Hilbert Transform (Quadrature) Coefficients (Odd Anti-Symmetric, Q15):
    wire signed [15:0] h_q [0:30];
    assign h_q[0]  = -16'sd45;  assign h_q[1]  = 16'sd0;    assign h_q[2]  = -16'sd95;
    assign h_q[3]  = 16'sd0;    assign h_q[4]  = -16'sd190; assign h_q[5]  = 16'sd0;
    assign h_q[6]  = -16'sd380; assign h_q[7]  = 16'sd0;    assign h_q[8]  = -16'sd750;
    assign h_q[9]  = 16'sd0;    assign h_q[10] = -16'sd1650;assign h_q[11] = 16'sd0;
    assign h_q[12] = -16'sd4400;assign h_q[13] = 16'sd0;    assign h_q[14] = -16'sd9800;
    assign h_q[15] = 16'sd0;    // Center zero tap
    assign h_q[16] = 16'sd9800; assign h_q[17] = 16'sd0;    assign h_q[18] = 16'sd4400;
    assign h_q[19] = 16'sd0;    assign h_q[20] = 16'sd1650; assign h_q[21] = 16'sd0;
    assign h_q[22] = 16'sd750;  assign h_q[23] = 16'sd0;    assign h_q[24] = 16'sd380;
    assign h_q[25] = 16'sd0;    assign h_q[26] = 16'sd190;  assign h_q[27] = 16'sd0;
    assign h_q[28] = 16'sd95;   assign h_q[29] = 16'sd0;    assign h_q[30] = 16'sd45;

    // Shift register for input samples
    reg signed [DATA_WIDTH-1:0] shift_reg [0:30];
    integer k;
    integer j;

    // Accumulators
    reg signed [31:0] sum_i;
    reg signed [31:0] sum_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (k = 0; k < 31; k = k + 1) shift_reg[k] <= 16'sd0;
            out_valid <= 1'b0;
            out_i     <= 16'sd0;
            out_q     <= 16'sd0;
        end else if (in_valid) begin
            // Shift pipeline
            shift_reg[0] <= in_symbol;
            for (k = 1; k < 31; k = k + 1) begin
                shift_reg[k] <= shift_reg[k-1];
            end

            // Compute FIR Convolution in Q15
            sum_i = 32'sd0;
            sum_q = 32'sd0;
            for (j = 0; j < 31; j = j + 1) begin
                sum_i = sum_i + (shift_reg[j] * h_i[j]);
                if (h_q[j] != 16'sd0)
                    sum_q = sum_q + (shift_reg[j] * h_q[j]);
            end
            out_valid <= 1'b1;
            out_i     <= sum_i[30:15]; // Scale back from Q15
            out_q     <= sum_q[30:15];
        end else begin
            out_valid <= 1'b0;
        end
    end

endmodule
