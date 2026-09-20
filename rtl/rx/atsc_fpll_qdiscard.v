// ============================================================================
// Module: atsc_fpll_qdiscard
// Target: Xilinx Spartan-6 (USRP B210 XC6SLX150)
// Description:
//   Hardware Frequency & Phase-Locked Loop (FPLL) for ATSC 1.0 (8VSB).
//   1. 256-entry Sin/Cos NCO with 32-bit Phase Accumulator.
//   2. Mixes incoming complex baseband I/Q to lock pilot tone to DC.
//   3. Discards Q channel and outputs real 16-bit 8VSB baseband symbols.
// ============================================================================

`timescale 1ns / 1ps

module atsc_fpll_qdiscard #(
    parameter DATA_WIDTH = 16,     // ADC bit depth (Q15 signed)
    parameter ACC_WIDTH  = 32,     // Phase accumulator bit depth
    parameter ALPHA_SHIFT = 6,     // Loop filter proportional gain shift
    parameter BETA_SHIFT  = 12     // Loop filter integral gain shift
)(
    input  wire                   clk,           // Master DSP clock (47.35 MHz)
    input  wire                   rst_n,         // Active-low reset
    input  wire                   in_valid,      // Input sample strobe (11.838 MSps)
    input  wire signed [DATA_WIDTH-1:0] in_i,     // Complex I from AD9361/RRC
    input  wire signed [DATA_WIDTH-1:0] in_q,     // Complex Q from AD9361/RRC
    
    // Output Real 8VSB Baseband Symbols
    output reg                    out_valid,
    output reg  signed [DATA_WIDTH-1:0] out_real,
    output reg  signed [DATA_WIDTH-1:0] out_q_err,
    output reg                    lock_detect
);

    localparam [ACC_WIDTH-1:0] NOMINAL_PILOT_FTW = 32'h3A2E8BA3; // +2.690559 MHz (Shifts pilot at -2.69 MHz to DC)

    reg [ACC_WIDTH-1:0] phase_acc;
    reg signed [ACC_WIDTH-1:0] freq_acc;
    
    reg signed [DATA_WIDTH-1:0] cos_lut [0:255];
    reg signed [DATA_WIDTH-1:0] sin_lut [0:255];
    initial begin
        cos_lut[  0] = 16'sh7FFF; sin_lut[  0] = 16'sh0000;
        cos_lut[  1] = 16'sh7FF5; sin_lut[  1] = 16'sh0324;
        cos_lut[  2] = 16'sh7FD8; sin_lut[  2] = 16'sh0648;
        cos_lut[  3] = 16'sh7FA6; sin_lut[  3] = 16'sh096A;
        cos_lut[  4] = 16'sh7F61; sin_lut[  4] = 16'sh0C8C;
        cos_lut[  5] = 16'sh7F09; sin_lut[  5] = 16'sh0FAB;
        cos_lut[  6] = 16'sh7E9C; sin_lut[  6] = 16'sh12C8;
        cos_lut[  7] = 16'sh7E1D; sin_lut[  7] = 16'sh15E2;
        cos_lut[  8] = 16'sh7D89; sin_lut[  8] = 16'sh18F9;
        cos_lut[  9] = 16'sh7CE3; sin_lut[  9] = 16'sh1C0B;
        cos_lut[ 10] = 16'sh7C29; sin_lut[ 10] = 16'sh1F1A;
        cos_lut[ 11] = 16'sh7B5C; sin_lut[ 11] = 16'sh2223;
        cos_lut[ 12] = 16'sh7A7C; sin_lut[ 12] = 16'sh2528;
        cos_lut[ 13] = 16'sh7989; sin_lut[ 13] = 16'sh2826;
        cos_lut[ 14] = 16'sh7884; sin_lut[ 14] = 16'sh2B1F;
        cos_lut[ 15] = 16'sh776B; sin_lut[ 15] = 16'sh2E11;
        cos_lut[ 16] = 16'sh7641; sin_lut[ 16] = 16'sh30FB;
        cos_lut[ 17] = 16'sh7504; sin_lut[ 17] = 16'sh33DF;
        cos_lut[ 18] = 16'sh73B5; sin_lut[ 18] = 16'sh36BA;
        cos_lut[ 19] = 16'sh7254; sin_lut[ 19] = 16'sh398C;
        cos_lut[ 20] = 16'sh70E2; sin_lut[ 20] = 16'sh3C56;
        cos_lut[ 21] = 16'sh6F5E; sin_lut[ 21] = 16'sh3F17;
        cos_lut[ 22] = 16'sh6DC9; sin_lut[ 22] = 16'sh41CE;
        cos_lut[ 23] = 16'sh6C23; sin_lut[ 23] = 16'sh447A;
        cos_lut[ 24] = 16'sh6A6D; sin_lut[ 24] = 16'sh471C;
        cos_lut[ 25] = 16'sh68A6; sin_lut[ 25] = 16'sh49B4;
        cos_lut[ 26] = 16'sh66CF; sin_lut[ 26] = 16'sh4C3F;
        cos_lut[ 27] = 16'sh64E8; sin_lut[ 27] = 16'sh4EBF;
        cos_lut[ 28] = 16'sh62F1; sin_lut[ 28] = 16'sh5133;
        cos_lut[ 29] = 16'sh60EB; sin_lut[ 29] = 16'sh539B;
        cos_lut[ 30] = 16'sh5ED7; sin_lut[ 30] = 16'sh55F5;
        cos_lut[ 31] = 16'sh5CB3; sin_lut[ 31] = 16'sh5842;
        cos_lut[ 32] = 16'sh5A82; sin_lut[ 32] = 16'sh5A82;
        cos_lut[ 33] = 16'sh5842; sin_lut[ 33] = 16'sh5CB3;
        cos_lut[ 34] = 16'sh55F5; sin_lut[ 34] = 16'sh5ED7;
        cos_lut[ 35] = 16'sh539B; sin_lut[ 35] = 16'sh60EB;
        cos_lut[ 36] = 16'sh5133; sin_lut[ 36] = 16'sh62F1;
        cos_lut[ 37] = 16'sh4EBF; sin_lut[ 37] = 16'sh64E8;
        cos_lut[ 38] = 16'sh4C3F; sin_lut[ 38] = 16'sh66CF;
        cos_lut[ 39] = 16'sh49B4; sin_lut[ 39] = 16'sh68A6;
        cos_lut[ 40] = 16'sh471C; sin_lut[ 40] = 16'sh6A6D;
        cos_lut[ 41] = 16'sh447A; sin_lut[ 41] = 16'sh6C23;
        cos_lut[ 42] = 16'sh41CE; sin_lut[ 42] = 16'sh6DC9;
        cos_lut[ 43] = 16'sh3F17; sin_lut[ 43] = 16'sh6F5E;
        cos_lut[ 44] = 16'sh3C56; sin_lut[ 44] = 16'sh70E2;
        cos_lut[ 45] = 16'sh398C; sin_lut[ 45] = 16'sh7254;
        cos_lut[ 46] = 16'sh36BA; sin_lut[ 46] = 16'sh73B5;
        cos_lut[ 47] = 16'sh33DF; sin_lut[ 47] = 16'sh7504;
        cos_lut[ 48] = 16'sh30FB; sin_lut[ 48] = 16'sh7641;
        cos_lut[ 49] = 16'sh2E11; sin_lut[ 49] = 16'sh776B;
        cos_lut[ 50] = 16'sh2B1F; sin_lut[ 50] = 16'sh7884;
        cos_lut[ 51] = 16'sh2826; sin_lut[ 51] = 16'sh7989;
        cos_lut[ 52] = 16'sh2528; sin_lut[ 52] = 16'sh7A7C;
        cos_lut[ 53] = 16'sh2223; sin_lut[ 53] = 16'sh7B5C;
        cos_lut[ 54] = 16'sh1F1A; sin_lut[ 54] = 16'sh7C29;
        cos_lut[ 55] = 16'sh1C0B; sin_lut[ 55] = 16'sh7CE3;
        cos_lut[ 56] = 16'sh18F9; sin_lut[ 56] = 16'sh7D89;
        cos_lut[ 57] = 16'sh15E2; sin_lut[ 57] = 16'sh7E1D;
        cos_lut[ 58] = 16'sh12C8; sin_lut[ 58] = 16'sh7E9C;
        cos_lut[ 59] = 16'sh0FAB; sin_lut[ 59] = 16'sh7F09;
        cos_lut[ 60] = 16'sh0C8C; sin_lut[ 60] = 16'sh7F61;
        cos_lut[ 61] = 16'sh096A; sin_lut[ 61] = 16'sh7FA6;
        cos_lut[ 62] = 16'sh0648; sin_lut[ 62] = 16'sh7FD8;
        cos_lut[ 63] = 16'sh0324; sin_lut[ 63] = 16'sh7FF5;
        cos_lut[ 64] = 16'sh0000; sin_lut[ 64] = 16'sh7FFF;
        cos_lut[ 65] = 16'shFCDC; sin_lut[ 65] = 16'sh7FF5;
        cos_lut[ 66] = 16'shF9B8; sin_lut[ 66] = 16'sh7FD8;
        cos_lut[ 67] = 16'shF696; sin_lut[ 67] = 16'sh7FA6;
        cos_lut[ 68] = 16'shF374; sin_lut[ 68] = 16'sh7F61;
        cos_lut[ 69] = 16'shF055; sin_lut[ 69] = 16'sh7F09;
        cos_lut[ 70] = 16'shED38; sin_lut[ 70] = 16'sh7E9C;
        cos_lut[ 71] = 16'shEA1E; sin_lut[ 71] = 16'sh7E1D;
        cos_lut[ 72] = 16'shE707; sin_lut[ 72] = 16'sh7D89;
        cos_lut[ 73] = 16'shE3F5; sin_lut[ 73] = 16'sh7CE3;
        cos_lut[ 74] = 16'shE0E6; sin_lut[ 74] = 16'sh7C29;
        cos_lut[ 75] = 16'shDDDD; sin_lut[ 75] = 16'sh7B5C;
        cos_lut[ 76] = 16'shDAD8; sin_lut[ 76] = 16'sh7A7C;
        cos_lut[ 77] = 16'shD7DA; sin_lut[ 77] = 16'sh7989;
        cos_lut[ 78] = 16'shD4E1; sin_lut[ 78] = 16'sh7884;
        cos_lut[ 79] = 16'shD1EF; sin_lut[ 79] = 16'sh776B;
        cos_lut[ 80] = 16'shCF05; sin_lut[ 80] = 16'sh7641;
        cos_lut[ 81] = 16'shCC21; sin_lut[ 81] = 16'sh7504;
        cos_lut[ 82] = 16'shC946; sin_lut[ 82] = 16'sh73B5;
        cos_lut[ 83] = 16'shC674; sin_lut[ 83] = 16'sh7254;
        cos_lut[ 84] = 16'shC3AA; sin_lut[ 84] = 16'sh70E2;
        cos_lut[ 85] = 16'shC0E9; sin_lut[ 85] = 16'sh6F5E;
        cos_lut[ 86] = 16'shBE32; sin_lut[ 86] = 16'sh6DC9;
        cos_lut[ 87] = 16'shBB86; sin_lut[ 87] = 16'sh6C23;
        cos_lut[ 88] = 16'shB8E4; sin_lut[ 88] = 16'sh6A6D;
        cos_lut[ 89] = 16'shB64C; sin_lut[ 89] = 16'sh68A6;
        cos_lut[ 90] = 16'shB3C1; sin_lut[ 90] = 16'sh66CF;
        cos_lut[ 91] = 16'shB141; sin_lut[ 91] = 16'sh64E8;
        cos_lut[ 92] = 16'shAECD; sin_lut[ 92] = 16'sh62F1;
        cos_lut[ 93] = 16'shAC65; sin_lut[ 93] = 16'sh60EB;
        cos_lut[ 94] = 16'shAA0B; sin_lut[ 94] = 16'sh5ED7;
        cos_lut[ 95] = 16'shA7BE; sin_lut[ 95] = 16'sh5CB3;
        cos_lut[ 96] = 16'shA57E; sin_lut[ 96] = 16'sh5A82;
        cos_lut[ 97] = 16'shA34D; sin_lut[ 97] = 16'sh5842;
        cos_lut[ 98] = 16'shA129; sin_lut[ 98] = 16'sh55F5;
        cos_lut[ 99] = 16'sh9F15; sin_lut[ 99] = 16'sh539B;
        cos_lut[100] = 16'sh9D0F; sin_lut[100] = 16'sh5133;
        cos_lut[101] = 16'sh9B18; sin_lut[101] = 16'sh4EBF;
        cos_lut[102] = 16'sh9931; sin_lut[102] = 16'sh4C3F;
        cos_lut[103] = 16'sh975A; sin_lut[103] = 16'sh49B4;
        cos_lut[104] = 16'sh9593; sin_lut[104] = 16'sh471C;
        cos_lut[105] = 16'sh93DD; sin_lut[105] = 16'sh447A;
        cos_lut[106] = 16'sh9237; sin_lut[106] = 16'sh41CE;
        cos_lut[107] = 16'sh90A2; sin_lut[107] = 16'sh3F17;
        cos_lut[108] = 16'sh8F1E; sin_lut[108] = 16'sh3C56;
        cos_lut[109] = 16'sh8DAC; sin_lut[109] = 16'sh398C;
        cos_lut[110] = 16'sh8C4B; sin_lut[110] = 16'sh36BA;
        cos_lut[111] = 16'sh8AFC; sin_lut[111] = 16'sh33DF;
        cos_lut[112] = 16'sh89BF; sin_lut[112] = 16'sh30FB;
        cos_lut[113] = 16'sh8895; sin_lut[113] = 16'sh2E11;
        cos_lut[114] = 16'sh877C; sin_lut[114] = 16'sh2B1F;
        cos_lut[115] = 16'sh8677; sin_lut[115] = 16'sh2826;
        cos_lut[116] = 16'sh8584; sin_lut[116] = 16'sh2528;
        cos_lut[117] = 16'sh84A4; sin_lut[117] = 16'sh2223;
        cos_lut[118] = 16'sh83D7; sin_lut[118] = 16'sh1F1A;
        cos_lut[119] = 16'sh831D; sin_lut[119] = 16'sh1C0B;
        cos_lut[120] = 16'sh8277; sin_lut[120] = 16'sh18F9;
        cos_lut[121] = 16'sh81E3; sin_lut[121] = 16'sh15E2;
        cos_lut[122] = 16'sh8164; sin_lut[122] = 16'sh12C8;
        cos_lut[123] = 16'sh80F7; sin_lut[123] = 16'sh0FAB;
        cos_lut[124] = 16'sh809F; sin_lut[124] = 16'sh0C8C;
        cos_lut[125] = 16'sh805A; sin_lut[125] = 16'sh096A;
        cos_lut[126] = 16'sh8028; sin_lut[126] = 16'sh0648;
        cos_lut[127] = 16'sh800B; sin_lut[127] = 16'sh0324;
        cos_lut[128] = 16'sh8001; sin_lut[128] = 16'sh0000;
        cos_lut[129] = 16'sh800B; sin_lut[129] = 16'shFCDC;
        cos_lut[130] = 16'sh8028; sin_lut[130] = 16'shF9B8;
        cos_lut[131] = 16'sh805A; sin_lut[131] = 16'shF696;
        cos_lut[132] = 16'sh809F; sin_lut[132] = 16'shF374;
        cos_lut[133] = 16'sh80F7; sin_lut[133] = 16'shF055;
        cos_lut[134] = 16'sh8164; sin_lut[134] = 16'shED38;
        cos_lut[135] = 16'sh81E3; sin_lut[135] = 16'shEA1E;
        cos_lut[136] = 16'sh8277; sin_lut[136] = 16'shE707;
        cos_lut[137] = 16'sh831D; sin_lut[137] = 16'shE3F5;
        cos_lut[138] = 16'sh83D7; sin_lut[138] = 16'shE0E6;
        cos_lut[139] = 16'sh84A4; sin_lut[139] = 16'shDDDD;
        cos_lut[140] = 16'sh8584; sin_lut[140] = 16'shDAD8;
        cos_lut[141] = 16'sh8677; sin_lut[141] = 16'shD7DA;
        cos_lut[142] = 16'sh877C; sin_lut[142] = 16'shD4E1;
        cos_lut[143] = 16'sh8895; sin_lut[143] = 16'shD1EF;
        cos_lut[144] = 16'sh89BF; sin_lut[144] = 16'shCF05;
        cos_lut[145] = 16'sh8AFC; sin_lut[145] = 16'shCC21;
        cos_lut[146] = 16'sh8C4B; sin_lut[146] = 16'shC946;
        cos_lut[147] = 16'sh8DAC; sin_lut[147] = 16'shC674;
        cos_lut[148] = 16'sh8F1E; sin_lut[148] = 16'shC3AA;
        cos_lut[149] = 16'sh90A2; sin_lut[149] = 16'shC0E9;
        cos_lut[150] = 16'sh9237; sin_lut[150] = 16'shBE32;
        cos_lut[151] = 16'sh93DD; sin_lut[151] = 16'shBB86;
        cos_lut[152] = 16'sh9593; sin_lut[152] = 16'shB8E4;
        cos_lut[153] = 16'sh975A; sin_lut[153] = 16'shB64C;
        cos_lut[154] = 16'sh9931; sin_lut[154] = 16'shB3C1;
        cos_lut[155] = 16'sh9B18; sin_lut[155] = 16'shB141;
        cos_lut[156] = 16'sh9D0F; sin_lut[156] = 16'shAECD;
        cos_lut[157] = 16'sh9F15; sin_lut[157] = 16'shAC65;
        cos_lut[158] = 16'shA129; sin_lut[158] = 16'shAA0B;
        cos_lut[159] = 16'shA34D; sin_lut[159] = 16'shA7BE;
        cos_lut[160] = 16'shA57E; sin_lut[160] = 16'shA57E;
        cos_lut[161] = 16'shA7BE; sin_lut[161] = 16'shA34D;
        cos_lut[162] = 16'shAA0B; sin_lut[162] = 16'shA129;
        cos_lut[163] = 16'shAC65; sin_lut[163] = 16'sh9F15;
        cos_lut[164] = 16'shAECD; sin_lut[164] = 16'sh9D0F;
        cos_lut[165] = 16'shB141; sin_lut[165] = 16'sh9B18;
        cos_lut[166] = 16'shB3C1; sin_lut[166] = 16'sh9931;
        cos_lut[167] = 16'shB64C; sin_lut[167] = 16'sh975A;
        cos_lut[168] = 16'shB8E4; sin_lut[168] = 16'sh9593;
        cos_lut[169] = 16'shBB86; sin_lut[169] = 16'sh93DD;
        cos_lut[170] = 16'shBE32; sin_lut[170] = 16'sh9237;
        cos_lut[171] = 16'shC0E9; sin_lut[171] = 16'sh90A2;
        cos_lut[172] = 16'shC3AA; sin_lut[172] = 16'sh8F1E;
        cos_lut[173] = 16'shC674; sin_lut[173] = 16'sh8DAC;
        cos_lut[174] = 16'shC946; sin_lut[174] = 16'sh8C4B;
        cos_lut[175] = 16'shCC21; sin_lut[175] = 16'sh8AFC;
        cos_lut[176] = 16'shCF05; sin_lut[176] = 16'sh89BF;
        cos_lut[177] = 16'shD1EF; sin_lut[177] = 16'sh8895;
        cos_lut[178] = 16'shD4E1; sin_lut[178] = 16'sh877C;
        cos_lut[179] = 16'shD7DA; sin_lut[179] = 16'sh8677;
        cos_lut[180] = 16'shDAD8; sin_lut[180] = 16'sh8584;
        cos_lut[181] = 16'shDDDD; sin_lut[181] = 16'sh84A4;
        cos_lut[182] = 16'shE0E6; sin_lut[182] = 16'sh83D7;
        cos_lut[183] = 16'shE3F5; sin_lut[183] = 16'sh831D;
        cos_lut[184] = 16'shE707; sin_lut[184] = 16'sh8277;
        cos_lut[185] = 16'shEA1E; sin_lut[185] = 16'sh81E3;
        cos_lut[186] = 16'shED38; sin_lut[186] = 16'sh8164;
        cos_lut[187] = 16'shF055; sin_lut[187] = 16'sh80F7;
        cos_lut[188] = 16'shF374; sin_lut[188] = 16'sh809F;
        cos_lut[189] = 16'shF696; sin_lut[189] = 16'sh805A;
        cos_lut[190] = 16'shF9B8; sin_lut[190] = 16'sh8028;
        cos_lut[191] = 16'shFCDC; sin_lut[191] = 16'sh800B;
        cos_lut[192] = 16'sh0000; sin_lut[192] = 16'sh8001;
        cos_lut[193] = 16'sh0324; sin_lut[193] = 16'sh800B;
        cos_lut[194] = 16'sh0648; sin_lut[194] = 16'sh8028;
        cos_lut[195] = 16'sh096A; sin_lut[195] = 16'sh805A;
        cos_lut[196] = 16'sh0C8C; sin_lut[196] = 16'sh809F;
        cos_lut[197] = 16'sh0FAB; sin_lut[197] = 16'sh80F7;
        cos_lut[198] = 16'sh12C8; sin_lut[198] = 16'sh8164;
        cos_lut[199] = 16'sh15E2; sin_lut[199] = 16'sh81E3;
        cos_lut[200] = 16'sh18F9; sin_lut[200] = 16'sh8277;
        cos_lut[201] = 16'sh1C0B; sin_lut[201] = 16'sh831D;
        cos_lut[202] = 16'sh1F1A; sin_lut[202] = 16'sh83D7;
        cos_lut[203] = 16'sh2223; sin_lut[203] = 16'sh84A4;
        cos_lut[204] = 16'sh2528; sin_lut[204] = 16'sh8584;
        cos_lut[205] = 16'sh2826; sin_lut[205] = 16'sh8677;
        cos_lut[206] = 16'sh2B1F; sin_lut[206] = 16'sh877C;
        cos_lut[207] = 16'sh2E11; sin_lut[207] = 16'sh8895;
        cos_lut[208] = 16'sh30FB; sin_lut[208] = 16'sh89BF;
        cos_lut[209] = 16'sh33DF; sin_lut[209] = 16'sh8AFC;
        cos_lut[210] = 16'sh36BA; sin_lut[210] = 16'sh8C4B;
        cos_lut[211] = 16'sh398C; sin_lut[211] = 16'sh8DAC;
        cos_lut[212] = 16'sh3C56; sin_lut[212] = 16'sh8F1E;
        cos_lut[213] = 16'sh3F17; sin_lut[213] = 16'sh90A2;
        cos_lut[214] = 16'sh41CE; sin_lut[214] = 16'sh9237;
        cos_lut[215] = 16'sh447A; sin_lut[215] = 16'sh93DD;
        cos_lut[216] = 16'sh471C; sin_lut[216] = 16'sh9593;
        cos_lut[217] = 16'sh49B4; sin_lut[217] = 16'sh975A;
        cos_lut[218] = 16'sh4C3F; sin_lut[218] = 16'sh9931;
        cos_lut[219] = 16'sh4EBF; sin_lut[219] = 16'sh9B18;
        cos_lut[220] = 16'sh5133; sin_lut[220] = 16'sh9D0F;
        cos_lut[221] = 16'sh539B; sin_lut[221] = 16'sh9F15;
        cos_lut[222] = 16'sh55F5; sin_lut[222] = 16'shA129;
        cos_lut[223] = 16'sh5842; sin_lut[223] = 16'shA34D;
        cos_lut[224] = 16'sh5A82; sin_lut[224] = 16'shA57E;
        cos_lut[225] = 16'sh5CB3; sin_lut[225] = 16'shA7BE;
        cos_lut[226] = 16'sh5ED7; sin_lut[226] = 16'shAA0B;
        cos_lut[227] = 16'sh60EB; sin_lut[227] = 16'shAC65;
        cos_lut[228] = 16'sh62F1; sin_lut[228] = 16'shAECD;
        cos_lut[229] = 16'sh64E8; sin_lut[229] = 16'shB141;
        cos_lut[230] = 16'sh66CF; sin_lut[230] = 16'shB3C1;
        cos_lut[231] = 16'sh68A6; sin_lut[231] = 16'shB64C;
        cos_lut[232] = 16'sh6A6D; sin_lut[232] = 16'shB8E4;
        cos_lut[233] = 16'sh6C23; sin_lut[233] = 16'shBB86;
        cos_lut[234] = 16'sh6DC9; sin_lut[234] = 16'shBE32;
        cos_lut[235] = 16'sh6F5E; sin_lut[235] = 16'shC0E9;
        cos_lut[236] = 16'sh70E2; sin_lut[236] = 16'shC3AA;
        cos_lut[237] = 16'sh7254; sin_lut[237] = 16'shC674;
        cos_lut[238] = 16'sh73B5; sin_lut[238] = 16'shC946;
        cos_lut[239] = 16'sh7504; sin_lut[239] = 16'shCC21;
        cos_lut[240] = 16'sh7641; sin_lut[240] = 16'shCF05;
        cos_lut[241] = 16'sh776B; sin_lut[241] = 16'shD1EF;
        cos_lut[242] = 16'sh7884; sin_lut[242] = 16'shD4E1;
        cos_lut[243] = 16'sh7989; sin_lut[243] = 16'shD7DA;
        cos_lut[244] = 16'sh7A7C; sin_lut[244] = 16'shDAD8;
        cos_lut[245] = 16'sh7B5C; sin_lut[245] = 16'shDDDD;
        cos_lut[246] = 16'sh7C29; sin_lut[246] = 16'shE0E6;
        cos_lut[247] = 16'sh7CE3; sin_lut[247] = 16'shE3F5;
        cos_lut[248] = 16'sh7D89; sin_lut[248] = 16'shE707;
        cos_lut[249] = 16'sh7E1D; sin_lut[249] = 16'shEA1E;
        cos_lut[250] = 16'sh7E9C; sin_lut[250] = 16'shED38;
        cos_lut[251] = 16'sh7F09; sin_lut[251] = 16'shF055;
        cos_lut[252] = 16'sh7F61; sin_lut[252] = 16'shF374;
        cos_lut[253] = 16'sh7FA6; sin_lut[253] = 16'shF696;
        cos_lut[254] = 16'sh7FD8; sin_lut[254] = 16'shF9B8;
        cos_lut[255] = 16'sh7FF5; sin_lut[255] = 16'shFCDC;
    end

    wire [7:0] lut_addr = phase_acc[ACC_WIDTH-1 : ACC_WIDTH-8];
    wire signed [DATA_WIDTH-1:0] cos_val = cos_lut[lut_addr];
    wire signed [DATA_WIDTH-1:0] sin_val = sin_lut[lut_addr];

    (* use_dsp48 = "no" *) reg signed [DATA_WIDTH-1:0] mixed_i;
    (* use_dsp48 = "no" *) reg signed [DATA_WIDTH-1:0] mixed_q;
    reg signed [DATA_WIDTH-1:0] phase_error;
    reg signed [ACC_WIDTH-1:0]  integrator;
    reg [15:0] lock_counter;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase_acc     <= 32'd0;
            freq_acc      <= NOMINAL_PILOT_FTW;
            integrator    <= 32'd0;
            out_valid     <= 1'b0;
            out_real      <= 16'd0;
            out_q_err     <= 16'd0;
            lock_detect   <= 1'b0;
            lock_counter  <= 16'd0;
        end else if (in_valid) begin
            phase_acc <= phase_acc + freq_acc;
            
            mixed_i <= (in_i * cos_val - in_q * sin_val) >>> (DATA_WIDTH - 1);
            mixed_q <= (in_q * cos_val + in_i * sin_val) >>> (DATA_WIDTH - 1);
            
            phase_error <= mixed_q;
            integrator  <= integrator - ($signed({{16{phase_error[DATA_WIDTH-1]}}, phase_error}) <<< 2);
            freq_acc    <= NOMINAL_PILOT_FTW + integrator - ($signed({{16{phase_error[DATA_WIDTH-1]}}, phase_error}) <<< 8);
            
            out_real    <= mixed_i;
            out_q_err   <= mixed_q;
            out_valid   <= 1'b1;
            
            if ($signed(mixed_q) > -256 && $signed(mixed_q) < 256) begin
                if (lock_counter < 16'hFFFF) lock_counter <= lock_counter + 1'b1;
            end else begin
                if (lock_counter > 16'd0) lock_counter <= lock_counter - 1'b1;
            end
            lock_detect <= (lock_counter > 16'h8000);
        end else begin
            out_valid <= 1'b0;
        end
    end

endmodule
