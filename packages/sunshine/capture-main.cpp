// Diagnostic-only entry point for Sunshine 2026.516.143833. The production
// package does not use this file. No server, input or audio initialization.
#include "config.h"
#include "globals.h"
#include "logging.h"
#include "video.h"

#include <atomic>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <set>
#include <stdexcept>
#include <string>
#include <thread>
#include <unistd.h>

using namespace std::chrono_literals;

namespace {
constexpr auto version = "2026.516.143833";
constexpr auto workdir = "/run/sw/user/sunshine-frames";
constexpr size_t max_bytes = 32 * 1024 * 1024;

struct pool_guard {
  ~pool_guard() {
    task_pool.stop();
    task_pool.join();
  }
};

// Apply the payload replacements that Sunshine's transport applies before
// packetization, but emit only the elementary video stream, without headers.
std::string payload(video::packet_raw_t &packet) {
  std::string data(reinterpret_cast<char *>(packet.data()), packet.data_size());
  if (packet.is_idr() && packet.replacements) {
    for (const auto &replacement : *packet.replacements) {
      if (replacement.old.empty()) {
        throw std::runtime_error("empty video replacement");
      }
      const auto offset = data.find(replacement.old);
      if (offset != std::string::npos) {
        data.replace(offset, replacement.old.size(), replacement._new);
      }
    }
  }
  return data;
}

void capture_codec(video::config_t config, const std::string &codec) {
  auto packets = mail::man->queue<video::packet_t>(mail::video_packets);
  while (packets->pop(0ms)) {} // Discard any startup-probe data.
  auto session = std::make_shared<safe::mail_raw_t>();
  auto shutdown = session->event<bool>(mail::shutdown);
  std::ofstream output(codec + ".video", std::ios::binary);
  output.exceptions(std::ios::failbit | std::ios::badbit);
  std::atomic<bool> finished = false;
  std::exception_ptr capture_error;
  int channel = 0;
  std::thread capture([&] {
    try {
      video::capture(session, config, &channel);
    } catch (...) {
      capture_error = std::current_exception();
    }
    finished = true;
  });
  size_t frames = 0;
  size_t bytes = 0;
  int64_t previous = -1;
  std::set<std::chrono::steady_clock::time_point> timestamps;
  const auto start = std::chrono::steady_clock::now();
  try {
    while (std::chrono::steady_clock::now() - start < 4s) {
      auto item = packets->pop(100ms);
      if (!item) {
        if (finished) {
          throw std::runtime_error("video capture exited before its deadline");
        }
        continue;
      }
      auto &packet = *item;
      if (packet.channel_data != &channel || packet.frame_index() <= previous ||
          (frames == 0 && !packet.is_idr())) {
        throw std::runtime_error("unexpected capture packet identity/order/keyframe");
      }
      previous = packet.frame_index();
      auto data = payload(packet);
      bytes += data.size();
      if (data.empty() || bytes > max_bytes || ++frames > 1024) {
        throw std::runtime_error("video packet/size limit exceeded");
      }
      output.write(data.data(), data.size());
      if (packet.frame_timestamp) {
        timestamps.insert(*packet.frame_timestamp);
      }
    }
  } catch (...) {
    shutdown->raise(true);
    capture.join();
    throw;
  }
  shutdown->raise(true);
  capture.join();
  output.close();
  if (capture_error) {
    std::rethrow_exception(capture_error);
  }
  if (frames < 20 || timestamps.size() < 3) {
    throw std::runtime_error("insufficient captured frames/timestamps");
  }
  std::ofstream report(codec + ".json");
  report.exceptions(std::ios::failbit | std::ios::badbit);
  report << "{\"codec\":\"" << codec << "\",\"frames\":" << frames
         << ",\"bytes\":" << bytes << ",\"capture_timestamps\":" << timestamps.size()
         << ",\"width\":" << config.width << ",\"height\":" << config.height
         << ",\"requested_fps\":" << config.framerate << "}\n";
}
} // namespace

int main(int argc, char **argv) {
  // This branch is the build-time, GPU-free smoke check.
  if (argc == 2 && std::string(argv[1]) == "--describe") {
    std::cout << "{\"kind\":\"sunshine-offline-capture\",\"version\":\"" << version
              << "\",\"engine_source_unchanged\":true,\"server_started\":false}\n";
    return 0;
  }
  try {
    if (argc != 3 || std::string(argv[1]) != "--capture" || geteuid() == 0 ||
        std::filesystem::current_path() != workdir) {
      throw std::runtime_error("use the private Sparkwerx capture-test wrapper");
    }
    video::config_t config {};
    const std::string preset = argv[2];
    if (preset != "1440p120" && preset != "4k60" && preset != "4k120") {
      throw std::runtime_error("unsupported capture preset");
    }
    config.width = preset == "1440p120" ? 2560 : 3840;
    config.height = preset == "1440p120" ? 1440 : 2160;
    config.framerate = preset == "4k60" ? 60 : 120;
    config.bitrate = preset == "1440p120" ? 40000 : (preset == "4k60" ? 60000 : 100000);
    config.slicesPerFrame = 1;
    config.numRefFrames = 1;
    config.encoderCscMode = 2; // BT.709 limited-range, SDR, 8-bit 4:2:0.
    // The parent also enforces 60 seconds and the entire service has 150.
    alarm(60);
    mail::man = std::make_shared<safe::mail_raw_t>();
    char config_path[] = "sunshine.conf";
    char *config_argv[] = {argv[0], config_path, nullptr};
    if (config::parse(2, config_argv) != 0 || config::video.capture != "wlr" ||
        config::video.encoder != "nvenc" || config::video.output_name != "SPARKWERX-REMOTE") {
      throw std::runtime_error("unexpected diagnostic capture configuration");
    }
    auto logging_guard = logging::init(config::sunshine.min_log_level, config::sunshine.log_file);
    BOOST_LOG(info) << "Sunshine version: " << version << " offline capture diagnostic";
    display_cursor = false;
    auto platform_guard = platf::init();
    if (!platform_guard) {
      throw std::runtime_error("platform initialization failed");
    }
    task_pool.start(1);
    pool_guard stop_pool;
    // Python requires the final NVENC-only success messages too: an upstream
    // fallback to a different encoder must never pass this diagnostic.
    if (video::probe_encoders() != 0) {
      throw std::runtime_error("encoder initialization failed");
    }
    const std::string codecs[] = {"h264", "hevc", "av1"};
    for (int index = 0; index < 3; ++index) {
      config.videoFormat = index;
      capture_codec(config, codecs[index]);
    }
    alarm(0);
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "FAIL|sunshine_frames|" << error.what() << '\n';
    return 1;
  }
}
