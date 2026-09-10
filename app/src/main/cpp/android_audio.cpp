#include "android_audio.h"

#include <aaudio/AAudio.h>

#include <android/log.h>

#include <atomic>
#include <chrono>
#include <deque>
#include <mutex>

#define LOG_TAG "EdgeTXAudio"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

namespace {

constexpr int kSampleRate = 32000;

std::mutex g_mu;
std::deque<int16_t> g_pending;
std::atomic<int64_t> g_playout_until_ms{0};

AAudioStream* g_stream = nullptr;
std::atomic<bool> g_running{false};

int64_t steadyNowMs() {
  using clock = std::chrono::steady_clock;
  return std::chrono::duration_cast<std::chrono::milliseconds>(
             clock::now().time_since_epoch())
      .count();
}

void extendPlayoutDeadline(int samples) {
  if (samples <= 0) return;
  const int64_t add_ms = (static_cast<int64_t>(samples) * 1000) / kSampleRate;
  const int64_t now = steadyNowMs();
  int64_t until = g_playout_until_ms.load(std::memory_order_relaxed);
  if (until < now) until = now;
  until += add_ms;
  g_playout_until_ms.store(until, std::memory_order_relaxed);
}

aaudio_data_callback_result_t dataCallback(AAudioStream* /*stream*/,
                                           void* /*userData*/,
                                           void* audioData,
                                           int32_t numFrames) {
  auto* out = static_cast<int16_t*>(audioData);
  std::lock_guard<std::mutex> lock(g_mu);
  for (int32_t i = 0; i < numFrames; ++i) {
    if (g_pending.empty()) {
      out[i] = 0;
    } else {
      out[i] = g_pending.front();
      g_pending.pop_front();
    }
  }
  return AAUDIO_CALLBACK_RESULT_CONTINUE;
}

void errorCallback(AAudioStream* stream, void* /*userData*/,
                   aaudio_result_t error) {
  if (error == AAUDIO_ERROR_DISCONNECTED) {
    LOGE("AAudio disconnected (%d)", error);
    if (stream) {
      AAudioStream_close(stream);
    }
    g_stream = nullptr;
    g_running.store(false, std::memory_order_release);
  }
}

bool openStream() {
  AAudioStreamBuilder* builder = nullptr;
  aaudio_result_t result = AAudio_createStreamBuilder(&builder);
  if (result != AAUDIO_OK || !builder) {
    LOGE("AAudio_createStreamBuilder failed (%d)", result);
    return false;
  }

  AAudioStreamBuilder_setDirection(builder, AAUDIO_DIRECTION_OUTPUT);
  AAudioStreamBuilder_setSharingMode(builder, AAUDIO_SHARING_MODE_SHARED);
  AAudioStreamBuilder_setSampleRate(builder, kSampleRate);
  AAudioStreamBuilder_setChannelCount(builder, 1);
  AAudioStreamBuilder_setFormat(builder, AAUDIO_FORMAT_PCM_I16);
  AAudioStreamBuilder_setPerformanceMode(builder,
                                         AAUDIO_PERFORMANCE_MODE_LOW_LATENCY);
  AAudioStreamBuilder_setDataCallback(builder, dataCallback, nullptr);
  AAudioStreamBuilder_setErrorCallback(builder, errorCallback, nullptr);

  result = AAudioStreamBuilder_openStream(builder, &g_stream);
  AAudioStreamBuilder_delete(builder);
  if (result != AAUDIO_OK || !g_stream) {
    LOGE("AAudioStreamBuilder_openStream failed (%d)", result);
    g_stream = nullptr;
    return false;
  }

  result = AAudioStream_requestStart(g_stream);
  if (result != AAUDIO_OK) {
    LOGE("AAudioStream_requestStart failed (%d)", result);
    AAudioStream_close(g_stream);
    g_stream = nullptr;
    return false;
  }

  return true;
}

}  // namespace

bool androidAudioInit() {
  if (g_running.load(std::memory_order_acquire)) {
    return g_stream != nullptr;
  }
  if (!openStream()) {
    return false;
  }
  g_running.store(true, std::memory_order_release);
  LOGI("AAudio started (%d Hz mono)", kSampleRate);
  return true;
}

void androidAudioDeinit() {
  androidAudioFlush();
  if (g_stream) {
    AAudioStream_requestStop(g_stream);
    AAudioStream_close(g_stream);
    g_stream = nullptr;
  }
  g_running.store(false, std::memory_order_release);
}

void androidAudioQueue(const uint8_t* buf, uint32_t len) {
  if (!buf || len < 2 || !g_running.load(std::memory_order_acquire)) return;
  const size_t n = len / sizeof(int16_t);
  const auto* samples = reinterpret_cast<const int16_t*>(buf);

  std::lock_guard<std::mutex> lock(g_mu);
  constexpr size_t kMaxSamples = static_cast<size_t>(kSampleRate) * 30u;
  if (g_pending.size() + n > kMaxSamples) {
    const size_t overflow = g_pending.size() + n - kMaxSamples;
    if (overflow >= g_pending.size()) {
      g_pending.clear();
    } else {
      g_pending.erase(g_pending.begin(),
                      g_pending.begin() +
                          static_cast<std::deque<int16_t>::difference_type>(
                              overflow));
    }
    LOGE("audio queue overflow, dropped %zu samples", overflow);
  }
  g_pending.insert(g_pending.end(), samples, samples + n);
  extendPlayoutDeadline(static_cast<int>(n));
}

int androidAudioBufferedMs() {
  std::lock_guard<std::mutex> lock(g_mu);
  return static_cast<int>((g_pending.size() * 1000u) / kSampleRate);
}

int androidAudioHostAudibleMs() {
  const int64_t now = steadyNowMs();
  int64_t tail = g_playout_until_ms.load(std::memory_order_relaxed) - now;
  if (tail < 0) tail = 0;
  return androidAudioBufferedMs() + static_cast<int>(tail);
}

void androidAudioFlush() {
  {
    std::lock_guard<std::mutex> lock(g_mu);
    g_pending.clear();
  }
  g_playout_until_ms.store(steadyNowMs(), std::memory_order_relaxed);
  // SDL_ClearQueuedAudio equivalent — callback outputs silence once the queue
  // is empty; no pause/flush/restart of the output device.
}
