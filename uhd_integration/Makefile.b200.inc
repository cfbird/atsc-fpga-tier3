# ============================================================================
# File: Makefile.b200.inc
# Target: USRP B200 / B210 FPGA Build (Xilinx Spartan-6 XC6SLX150)
# ============================================================================

CUSTOM_SRCS = $(addprefix $(abspath .)/, \
atsc_constants.vh \
atsc_rrc_filter.v \
atsc_fpll_qdiscard.v \
atsc_dc_blocker_agc.v \
atsc_sync_timing.v \
atsc_fs_checker.v \
atsc_equalizer.v \
atsc_viterbi_decoder.v \
atsc_deinterleaver.v \
atsc_rs_decoder.v \
atsc_derandomizer.v \
atsc_depad.v \
atsc_rx_tier3_top.v \
atsc_tx_randomizer.v \
atsc_tx_rs_encoder.v \
atsc_tx_interleaver.v \
atsc_tx_trellis_encoder.v \
atsc_tx_sync_mux.v \
atsc_tx_pilot_adder.v \
atsc_tx_rrc_filter.v \
atsc_tx_tier3_top.v)

CUSTOM_DEFS = ATSC_TIER3_RX=1 ATSC_TIER3_TX=1
