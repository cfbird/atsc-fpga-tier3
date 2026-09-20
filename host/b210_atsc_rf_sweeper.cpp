// ============================================================================
// File: b210_atsc_rf_sweeper.cpp
// Target: USRP B210 ATSC RF Frontend Sweep & Calibration Engine
// Description:
//   Sweeps RF center frequencies and AD9361 RX gain levels to locate the ATSC
//   pilot tone, measure TEI (Transport Error Indicator) BER rates, and identify
//   the optimal hardware operating point for error-free MPEG-TS decoding.
// ============================================================================

#include <iostream>
#include <iomanip>
#include <vector>
#include <map>
#include <string>
#include <chrono>
#include <thread>
#include <cmath>
#include <csignal>
#include <cstring>
#include <algorithm>

#include <uhd/usrp/multi_usrp.hpp>
#include <uhd/types/tune_request.hpp>

static bool g_running = true;

void sig_handler(int) {
    g_running = false;
}

struct SweepResult {
    double freq_mhz;
    double freq_offset_khz;
    double gain_db;
    size_t total_packets;
    size_t sync_ok_packets;
    size_t tei_error_packets;
    size_t pat_packets;      // PID 0x0000
    size_t psip_packets;     // PID 0x1FFB
    size_t pmt_video_packets;// PID 0x0030, 0x0031, etc.
    double tei_rate_pct;
    double sync_rate_pct;
    std::map<uint16_t, size_t> pid_counts;
};

int main(int argc, char* argv[]) {
    int channel = 15; // KNPB Channel 15 (479.0 MHz)
    std::string fpga_path = "/home/user1/uhd_images/usrp_b210_fpga.bin";

    if (argc > 1) channel = std::atoi(argv[1]);
    if (argc > 2) fpga_path = argv[2];

    double center_freq = (channel * 6.0 + 389.0) * 1e6;
    if (channel < 14 || channel > 36) center_freq = 479.0e6;

    double atsc_sym_rate = 4.5e6 / 286.0 * 684.0;
    double sample_rate = atsc_sym_rate * 1.1; // 11.838462 MSps

    std::cout << "==============================================================================" << std::endl;
    std::cout << "  USRP B210 ZERO-CPU ATSC 8VSB RF FRONTEND SWEEPER & CALIBRATION ENGINE       " << std::endl;
    std::cout << "==============================================================================" << std::endl;
    std::cout << "[*] ATSC RF Channel:   Channel " << channel << " (" << (center_freq / 1e6) << " MHz)" << std::endl;
    std::cout << "[*] Pilot Center:      " << ((center_freq - 2.690559e6) / 1e6) << " MHz" << std::endl;
    std::cout << "[*] Sample Clock Rate: " << (sample_rate / 1e6) << " MSps" << std::endl;
    std::cout << "==============================================================================" << std::endl;

    setenv("UHD_IMAGES_DIR", "/home/user1/uhd_images", 1);

    std::string device_args = "serial=30F7DBD,fpga=" + fpga_path;
    std::cout << "[*] Initializing USRP B210..." << std::endl;
    uhd::usrp::multi_usrp::sptr usrp;
    try {
        usrp = uhd::usrp::multi_usrp::make(device_args);
    } catch (const std::exception& e) {
        std::cerr << "[!] Error initializing USRP: " << e.what() << std::endl;
        return 1;
    }

    usrp->set_rx_rate(sample_rate);
    usrp->set_rx_antenna("TX/RX");

    uhd::stream_args_t stream_args("sc16", "sc16");
    stream_args.channels = {0};
    uhd::rx_streamer::sptr rx_stream = usrp->get_rx_stream(stream_args);

    std::signal(SIGINT, sig_handler);

    // Frequency offsets to test (-200 kHz to +200 kHz in 25 kHz steps)
    std::vector<double> freq_offsets_khz = {
        -200.0, -150.0, -100.0, -75.0, -50.0, -25.0, 0.0, 25.0, 50.0, 75.0, 100.0, 150.0, 200.0
    };

    // Gains to sweep (20 dB to 70 dB in 5 dB steps)
    std::vector<double> gains_db = {
        20.0, 25.0, 30.0, 35.0, 40.0, 45.0, 50.0, 55.0, 60.0, 65.0, 70.0
    };

    std::vector<SweepResult> all_results;
    SweepResult best_result{};
    best_result.tei_rate_pct = 100.0;

    const size_t max_samps = rx_stream->get_max_num_samps();
    std::vector<uint32_t> rx_buffer(max_samps * 4);
    std::vector<uint8_t> ts_accum;
    ts_accum.reserve(65536);

    std::cout << "\n" << std::left
              << std::setw(10) << "Gain(dB)"
              << std::setw(14) << "Offset(kHz)"
              << std::setw(14) << "Freq(MHz)"
              << std::setw(12) << "Sync Lock%"
              << std::setw(12) << "TEI Err%"
              << std::setw(10) << "PAT(0x00)"
              << std::setw(10) << "PSIP"
              << std::setw(12) << "Video PIDs"
              << "Status" << std::endl;
    std::cout << std::string(90, '-') << std::endl;

    for (double g : gains_db) {
        if (!g_running) break;
        usrp->set_rx_gain(g);

        for (double f_off_khz : freq_offsets_khz) {
            if (!g_running) break;

            double test_freq = center_freq + (f_off_khz * 1e3);
            usrp->set_rx_freq(uhd::tune_request_t(test_freq));

            // Start stream for evaluation
            uhd::stream_cmd_t start_cmd(uhd::stream_cmd_t::STREAM_MODE_START_CONTINUOUS);
            start_cmd.stream_now = true;
            rx_stream->issue_stream_cmd(start_cmd);

            // Settle settling time
            std::this_thread::sleep_for(std::chrono::milliseconds(50));

            SweepResult res{};
            res.freq_mhz = test_freq / 1e6;
            res.freq_offset_khz = f_off_khz;
            res.gain_db = g;
            ts_accum.clear();

            auto t_eval_start = std::chrono::steady_clock::now();
            bool in_sync = false;

            while (g_running) {
                auto now = std::chrono::steady_clock::now();
                if (std::chrono::duration<double>(now - t_eval_start).count() > 0.3) break; // 300ms evaluation window

                uhd::rx_metadata_t md;
                size_t n = rx_stream->recv(rx_buffer.data(), max_samps, md, 0.1);
                if (n == 0) continue;

                const uint8_t* raw = reinterpret_cast<const uint8_t*>(rx_buffer.data());
                ts_accum.insert(ts_accum.end(), raw, raw + (n * 4));

                // Find 0x47 sync
                if (!in_sync) {
                    if (ts_accum.size() < 188 * 4) continue;
                    for (size_t i = 0; i < 188; i++) {
                        if (ts_accum[i] == 0x47 &&
                            ts_accum[i+188] == 0x47 &&
                            ts_accum[i+376] == 0x47) {
                            ts_accum.erase(ts_accum.begin(), ts_accum.begin() + i);
                            in_sync = true;
                            break;
                        }
                    }
                    if (!in_sync) {
                        if (ts_accum.size() > 188 * 4) {
                            ts_accum.erase(ts_accum.begin(), ts_accum.end() - 188 * 3);
                        }
                        continue;
                    }
                }

                // Analyze framed 188-byte packets
                while (ts_accum.size() >= 188) {
                    const uint8_t* pkt = ts_accum.data();
                    res.total_packets++;
                    if (pkt[0] == 0x47) {
                        res.sync_ok_packets++;
                    } else {
                        in_sync = false;
                        break;
                    }

                    uint8_t tei = (pkt[1] >> 7) & 0x01;
                    if (tei) res.tei_error_packets++;

                    uint16_t pid = ((pkt[1] & 0x1F) << 8) | pkt[2];
                    res.pid_counts[pid]++;

                    if (pid == 0x0000) res.pat_packets++;
                    if (pid == 0x1FFB) res.psip_packets++;
                    if (pid == 0x0030 || pid == 0x0031 || pid == 0x0041 || pid == 0x0051) res.pmt_video_packets++;

                    ts_accum.erase(ts_accum.begin(), ts_accum.begin() + 188);
                }
            }

            // Stop stream
            uhd::stream_cmd_t stop_cmd(uhd::stream_cmd_t::STREAM_MODE_STOP_CONTINUOUS);
            rx_stream->issue_stream_cmd(stop_cmd);

            // Compute statistics
            if (res.total_packets > 0) {
                res.sync_rate_pct = (res.sync_ok_packets * 100.0) / res.total_packets;
                res.tei_rate_pct  = (res.tei_error_packets * 100.0) / res.total_packets;
            } else {
                res.sync_rate_pct = 0.0;
                res.tei_rate_pct = 100.0;
            }

            std::string status = "NO SIGNAL";
            if (res.sync_rate_pct > 95.0) {
                if (res.pat_packets > 0 || res.psip_packets > 0) status = "PAT/PSIP LOCKED!";
                else if (res.tei_rate_pct < 40.0) status = "LOW TEI";
                else status = "SYNC LOCKED";
            }

            std::cout << std::left
                      << std::setw(10) << std::fixed << std::setprecision(1) << res.gain_db
                      << std::setw(14) << std::fixed << std::setprecision(1) << res.freq_offset_khz
                      << std::setw(14) << std::fixed << std::setprecision(3) << res.freq_mhz
                      << std::setw(12) << std::fixed << std::setprecision(1) << res.sync_rate_pct
                      << std::setw(12) << std::fixed << std::setprecision(1) << res.tei_rate_pct
                      << std::setw(10) << res.pat_packets
                      << std::setw(10) << res.psip_packets
                      << std::setw(12) << res.pmt_video_packets
                      << status << std::endl;

            all_results.push_back(res);
            if (res.pat_packets > best_result.pat_packets ||
                (res.pat_packets == best_result.pat_packets && res.tei_rate_pct < best_result.tei_rate_pct && res.total_packets > 100)) {
                best_result = res;
            }
        }
    }

    std::cout << "==============================================================================" << std::endl;
    std::cout << "  CALIBRATION SWEEP COMPLETE                                                  " << std::endl;
    std::cout << "==============================================================================" << std::endl;
    std::cout << "[+] Optimal RF Front-End Settings:" << std::endl;
    std::cout << "    - Optimal RX Gain:       " << best_result.gain_db << " dB" << std::endl;
    std::cout << "    - Optimal Center Freq:   " << best_result.freq_mhz << " MHz (Offset: " << best_result.freq_offset_khz << " kHz)" << std::endl;
    std::cout << "    - Sync Lock Rate:        " << best_result.sync_rate_pct << " %" << std::endl;
    std::cout << "    - Best TEI Error Rate:   " << best_result.tei_rate_pct << " %" << std::endl;
    std::cout << "    - Detected PAT Packets:  " << best_result.pat_packets << std::endl;
    std::cout << "    - Detected PSIP Packets: " << best_result.psip_packets << std::endl;
    std::cout << "==============================================================================" << std::endl;

    return 0;
}
