// ============================================================================
// File: radio_legacy_atsc_patch.v
// Integration: Ettus USRP B210 (radio_legacy.v in uhd/fpga/usrp3/lib/radio_200/)
// Description:
//   Connects the Tier 3 ATSC 8VSB Hardware Demodulator directly between the
//   AD9361 RFIC complex baseband frontend and the VITA 49 new_rx_framer.
//   Bypasses host CPU DSP completely.
// ============================================================================

`ifdef ENABLE_ATSC_RX
generate
if (ENABLE_ATSC_RX) begin : gen_atsc_rx
   wire atsc_ts_valid;
   wire [7:0] atsc_ts_byte;
   wire atsc_ts_sync_strobe;
   wire atsc_fpll_locked;
   wire atsc_field_sync_detected;

   // Modulo-4 sample clock divider: 47.353848 MHz radio_clk -> 11.838462 MSps ATSC baseband
   reg [1:0] sample_div_cnt;
   always @(posedge radio_clk) begin
       if (radio_rst) sample_div_cnt <= 2'd0;
       else sample_div_cnt <= sample_div_cnt + 1'b1;
   end
   wire rx_sample_valid = (sample_div_cnt == 2'd3);

   // Top-Level ATSC 8VSB Physical Layer Demodulator Core
   atsc_rx_tier3_top #(
       .DATA_WIDTH(16)
   ) inst_atsc_demod (
       .clk(radio_clk),
       .rst_n(~radio_rst),
       .in_valid(rx_sample_valid),
       .in_i(rx_fe[31:16]),
       .in_q(rx_fe[15:0]),
       .out_ts_valid(atsc_ts_valid),
       .out_ts_byte(atsc_ts_byte),
       .out_ts_sync_strobe(atsc_ts_sync_strobe),
       .fpll_locked(atsc_fpll_locked),
       .field_sync_detected(atsc_field_sync_detected)
   );

   // Pack decoded MPEG-TS bytes (4 bytes -> 32-bit word) into VITA 49 framing
   reg [31:0] atsc_ts_packed;
   reg [1:0]  atsc_ts_cnt;
   reg        atsc_ts_strobe_r;

   always @(posedge radio_clk) begin
       if (radio_rst) begin
           atsc_ts_cnt      <= 2'd0;
           atsc_ts_strobe_r <= 1'b0;
           atsc_ts_packed   <= 32'd0;
       end else begin
           atsc_ts_strobe_r <= 1'b0;
           if (atsc_ts_valid) begin
               atsc_ts_packed <= {atsc_ts_packed[23:0], atsc_ts_byte};
               if (atsc_ts_cnt == 2'd3) begin
                   atsc_ts_cnt      <= 2'd0;
                   atsc_ts_strobe_r <= 1'b1;
               end else begin
                   atsc_ts_cnt <= atsc_ts_cnt + 1'b1;
               end
           end
       end
   end

   assign sample_rx = atsc_ts_packed;
   assign strobe_rx = atsc_ts_strobe_r;
   assign debug_ddc_chain = {14'd0, atsc_field_sync_detected, atsc_fpll_locked, atsc_ts_cnt, atsc_ts_packed[13:0]};
end else begin : gen_normal_ddc
   ddc_chain #(.BASE(SR_RX_DSP), .DSPNO(0), .WIDTH(24), .NEW_HB_DECIM(NEW_HB_DECIM), .DEVICE(DEVICE)) ddc_chain
     (.clk(radio_clk), .rst(radio_rst), .clr(1'b0),
      .set_stb(set_stb),.set_addr(set_addr),.set_data(set_data),
      .rx_fe_i({rx_fe[31:16],8'd0}),.rx_fe_q({rx_fe[15:0],8'd0}),
      .sample(sample_rx), .run(run_rx), .strobe(strobe_rx),
      .debug(debug_ddc_chain) );
end
endgenerate
`endif
