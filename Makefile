# ============================================================================
# Makefile for ATSC FPGA Tier 3 Radio-on-Chip
# ============================================================================

CC ?= gcc
CXX ?= g++
CXXFLAGS ?= -O3 -Wall -std=c++17
LDFLAGS ?= -luhd -lpthread

.PHONY: all streamer sim clean

all: streamer

streamer: host/b210_fpga_atsc_streamer.cpp
	$(CXX) $(CXXFLAGS) $< -o bin/b210_fpga_atsc_streamer $(LDFLAGS)

sim:
	cd sim && fuse -prj sim.prj -o tb_sim work.tb_atsc_demod && ./tb_sim -tclbatch <(echo "run all; exit")

clean:
	rm -rf bin/b210_fpga_atsc_streamer sim/tb_sim sim/isim sim/*.wdb sim/*.cmd
