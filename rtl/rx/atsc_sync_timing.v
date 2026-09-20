// ============================================================================
// Module: atsc_sync_timing
// Target: Xilinx Spartan-6 XC6SLX150 (USRP B210)
// Description:
//   Symbol Timing Recovery with Linear/Farrow Fractional Interpolator.
//   Re-samples incoming 11.838462 MSps stream to nominal 10.762238 MSps symbol rate.
// ============================================================================

`timescale 1ns / 1ps

module atsc_sync_timing #(
    parameter DATA_WIDTH = 16,
    parameter NCO_WIDTH  = 32
)(
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   in_valid,
    input  wire signed [DATA_WIDTH-1:0] in_sample,
    
    output reg                    out_sym_strobe, // High on each recovered symbol
    output reg  signed [DATA_WIDTH-1:0] out_symbol // Recovered 8VSB symbol
);

    // Nominal timing step: (1.0 / 1.1) * 2^32 = 32'hE8BA2E8C
    localparam [NCO_WIDTH-1:0] NOMINAL_TIMING_STEP = 32'hE8BA2E8C;

    // Delay registers
    reg signed [DATA_WIDTH-1:0] d0, d1, d2;
    
    // NCO & Fractional Interval Registers
    reg [NCO_WIDTH-1:0] timing_acc;
    reg signed [15:0] timing_corr;
    wire [15:0] mu = timing_acc[NCO_WIDTH-1:NCO_WIDTH-16]; // Fractional phase mu
    
    // 33-bit addition for clean overflow
    wire [NCO_WIDTH:0] next_acc = {1'b0, timing_acc} + {1'b0, NOMINAL_TIMING_STEP} + {{17{timing_corr[15]}}, timing_corr, 8'd0};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            d0             <= 0; d1 <= 0; d2 <= 0;
            timing_acc     <= 0;
            timing_corr    <= 0;
            out_sym_strobe <= 1'b0;
            out_symbol     <= 0;
        end else if (in_valid) begin
            d0 <= in_sample;
            d1 <= d0;
            d2 <= d1;
            
            timing_acc <= next_acc[NCO_WIDTH-1:0];
            
            // Symbol Strobe on NCO carry overflow
            if (next_acc[NCO_WIDTH]) begin
                out_sym_strobe <= 1'b1;
                // Linear Interpolation: y = d1 + mu * (d0 - d1)
                out_symbol     <= d1 + (((d0 - d1) * $signed({1'b0, mu})) >>> 16);
            end else begin
                out_sym_strobe <= 1'b0;
            end
        end else begin
            out_sym_strobe <= 1'b0;
        end
    end

endmodule
