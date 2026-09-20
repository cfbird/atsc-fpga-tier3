`timescale 1ns / 1ps

module tb_atsc_demod;

    reg clk;
    reg rst_n;
    reg in_valid;
    reg signed [15:0] in_i;
    reg signed [15:0] in_q;
    
    wire out_ts_valid;
    wire [7:0] out_ts_byte;
    wire out_ts_sync_strobe;
    wire fpll_locked;
    wire field_sync_detected;

    atsc_rx_tier3_top uut (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .in_i(in_i),
        .in_q(in_q),
        .out_ts_valid(out_ts_valid),
        .out_ts_byte(out_ts_byte),
        .out_ts_sync_strobe(out_ts_sync_strobe),
        .fpll_locked(fpll_locked),
        .field_sync_detected(field_sync_detected)
    );

    always #10.558 clk = ~clk;

    integer cnt_in_valid = 0;
    integer cnt_rrc = 0;
    integer cnt_fpll = 0;
    integer cnt_agc = 0;
    integer cnt_timing = 0;
    integer cnt_fs = 0;
    integer cnt_eq = 0;
    integer cnt_vit = 0;
    integer cnt_deint = 0;
    integer cnt_rs = 0;
    integer cnt_derand = 0;
    integer cnt_ts = 0;

    integer clk_cnt = 0;

    initial begin
        clk = 0;
        rst_n = 0;
        in_valid = 0;
        in_i = 16'sh1000;
        in_q = 16'sh0800;
        
        #100;
        rst_n = 1;
        
        #500000; // 500 us simulation
        $display("=== PIPELINE STAGE COUNTERS ===");
        $display("in_valid:    %d", cnt_in_valid);
        $display("rrc_valid:   %d", cnt_rrc);
        $display("fpll_valid:  %d", cnt_fpll);
        $display("agc_valid:   %d", cnt_agc);
        $display("timing_valid:%d", cnt_timing);
        $display("fs_valid:    %d", cnt_fs);
        $display("eq_valid:    %d", cnt_eq);
        $display("vit_valid:   %d", cnt_vit);
        $display("deint_valid: %d", cnt_deint);
        $display("rs_valid:    %d", cnt_rs);
        $display("derand_valid:%d", cnt_derand);
        $display("ts_valid:    %d", cnt_ts);
        $finish;
    end

    always @(posedge clk) begin
        if (rst_n) begin
            clk_cnt <= clk_cnt + 1;
            if ((clk_cnt % 4) == 3) begin
                in_valid <= 1'b1;
                in_i <= 16'sh2000 + (clk_cnt % 256);
                in_q <= 16'sh1000 - (clk_cnt % 256);
            end else begin
                in_valid <= 1'b0;
            end
            
            if (in_valid) cnt_in_valid <= cnt_in_valid + 1;
            if (uut.rrc_valid) cnt_rrc <= cnt_rrc + 1;
            if (uut.fpll_valid) cnt_fpll <= cnt_fpll + 1;
            if (uut.agc_valid) cnt_agc <= cnt_agc + 1;
            if (uut.timing_valid) cnt_timing <= cnt_timing + 1;
            if (uut.fs_valid) cnt_fs <= cnt_fs + 1;
            if (uut.eq_valid) cnt_eq <= cnt_eq + 1;
            if (uut.vit_byte_valid) cnt_vit <= cnt_vit + 1;
            if (uut.deint_valid) cnt_deint <= cnt_deint + 1;
            if (uut.rs_valid) cnt_rs <= cnt_rs + 1;
            if (uut.derand_valid) cnt_derand <= cnt_derand + 1;
            if (out_ts_valid) cnt_ts <= cnt_ts + 1;
        end
    end

endmodule
