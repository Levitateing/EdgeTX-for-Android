#include "edgetx_host.h"

#include "android_audio.h"
#include "simulib.h"

#include <algorithm>
#include <cstring>
#include <signal.h>
#include <unistd.h>

#include <android/log.h>

#define LOG_TAG "EdgeTXNative"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// COLORLCD direct-mode framebuffer (see simulcd.cpp).
extern uint16_t* simuLcdBuf;

namespace {

struct SimuStartArgs {
  bool tests;
  int32_t utc_offset;
};

void nativeCrashHandler(int sig, siginfo_t* info, void*) {
  LOGE("native crash signal=%d addr=%p", sig,
       info ? info->si_addr : nullptr);
  _exit(128 + sig);
}

void installNativeCrashHandler() {
  static bool installed = false;
  if (installed) return;
  installed = true;
  struct sigaction sa{};
  sa.sa_sigaction = nativeCrashHandler;
  sigemptyset(&sa.sa_mask);
  sa.sa_flags = SA_SIGINFO | SA_ONSTACK;
  sigaction(SIGSEGV, &sa, nullptr);
  sigaction(SIGABRT, &sa, nullptr);
  sigaction(SIGBUS, &sa, nullptr);
}

void* simu_thread_entry(void* arg) {
  auto* params = static_cast<SimuStartArgs*>(arg);
  const bool tests = params->tests;
  const int32_t utc = params->utc_offset;
  delete params;

  // simuMain() runs synchronously inside simuStart and needs a large stack
  // (LVGL init). JVM/Kotlin worker threads only have ~1 MB native stack.
  LOGI("simuStart thread begin");
  simuStart(tests, utc);
  LOGI("simuStart thread end");
  return nullptr;
}

}  // namespace

EdgeTXHost& EdgeTXHost::instance() {
  static EdgeTXHost host;
  return host;
}

EdgeTXHost::~EdgeTXHost() { stop(); }

void EdgeTXHost::setStoragePaths(const std::string& sdPath,
                                 const std::string& settingsPath) {
  sd_path_ = sdPath;
  settings_path_ = settingsPath;
  LOGI("storage sd='%s' settings='%s'", sd_path_.c_str(),
       settings_path_.c_str());
}

int16_t EdgeTXHost::getAnalog(uint8_t idx) {
  if (idx >= 32) return 2048;
  if (!analogs_inited_) {
    for (int i = 0; i < 32; i++) analogs_[i] = 2048;
    analogs_inited_ = true;
  }
  return analogs_[idx];
}

void EdgeTXHost::setAnalog(uint8_t idx, int16_t adcValue) {
  if (idx >= 32) return;
  if (!analogs_inited_) {
    for (int i = 0; i < 32; i++) analogs_[i] = 2048;
    analogs_inited_ = true;
  }
  if (adcValue < 0) adcValue = 0;
  if (adcValue > 4096) adcValue = 4096;
  analogs_[idx] = adcValue;
}

void EdgeTXHost::setBattery(uint16_t voltage10mV, bool plugged, bool charging) {
  battery_voltage_10mv_.store(voltage10mV, std::memory_order_relaxed);
  usb_plugged_.store(plugged, std::memory_order_relaxed);
  usb_charging_.store(charging, std::memory_order_relaxed);
  battery_valid_.store(true, std::memory_order_release);
}

void EdgeTXHost::trace(const char* text) {
  if (text) LOGI("FW: %s", text);
}

void EdgeTXHost::lcdNotify() {
  std::lock_guard<std::recursive_mutex> lock(mu_);
  refreshLcdLocked();
  lcd_dirty_.store(true, std::memory_order_release);
}

bool EdgeTXHost::init(std::string* err) {
  installNativeCrashHandler();
  std::lock_guard<std::recursive_mutex> lock(mu_);
  last_error_.clear();

  simuInit();
  if (!androidAudioInit()) {
    last_error_ = "AAudio init failed";
    if (err) *err = last_error_;
    LOGE("%s", last_error_.c_str());
    return false;
  }
  initialized_ = true;

  lcd_w_ = simuLcdGetWidth();
  lcd_h_ = simuLcdGetHeight();
  lcd_depth_ = simuLcdGetDepth();

  if (lcd_depth_ == 1)
    lcd_raw_size_ = lcd_w_ * ((lcd_h_ + 7) / 8);
  else if (lcd_depth_ == 4)
    lcd_raw_size_ = lcd_w_ * lcd_h_ / 2;
  else
    lcd_raw_size_ = lcd_w_ * lcd_h_ * (lcd_depth_ / 8);

  lcd_raw_.assign(lcd_raw_size_, 0);
  lcd_argb_.assign(static_cast<size_t>(lcd_w_) * lcd_h_, 0);
  lcd_has_frame_ = false;
  lcd_dirty_.store(false);

  LOGI("LCD %ux%u depth=%u raw=%u", lcd_w_, lcd_h_, lcd_depth_, lcd_raw_size_);
  return true;
}

bool EdgeTXHost::prepareStorage(std::string* err) {
  std::lock_guard<std::recursive_mutex> lock(mu_);
  last_error_.clear();
  if (!initialized_) {
    last_error_ = "not initialized";
    if (err) *err = last_error_;
    return false;
  }
  if (sd_path_.empty()) {
    last_error_ = "SD path empty";
    if (err) *err = last_error_;
    return false;
  }
  const std::string& settings =
      settings_path_.empty() ? sd_path_ : settings_path_;
  simuFatfsSetPaths(sd_path_.c_str(), settings.c_str());
  LOGI("simuFatfsSetPaths ok");
  return true;
}

bool EdgeTXHost::start(bool tests, int32_t utcOffset, std::string* err) {
  last_error_.clear();
  if (!initialized_) {
    last_error_ = "not initialized";
    if (err) *err = last_error_;
    return false;
  }
  if (simu_thread_started_) {
    return true;
  }

  pthread_attr_t attr;
  pthread_attr_init(&attr);
  pthread_attr_setstacksize(&attr, 8 * 1024 * 1024);

  auto* args = new SimuStartArgs{tests, utcOffset};
  const int rc =
      pthread_create(&simu_thread_, &attr, simu_thread_entry, args);
  pthread_attr_destroy(&attr);

  if (rc != 0) {
    delete args;
    last_error_ = "pthread_create failed: " + std::to_string(rc);
    LOGE("%s", last_error_.c_str());
    if (err) *err = last_error_;
    return false;
  }

  simu_thread_started_ = true;
  LOGI("simu firmware thread started");
  return true;
}

void EdgeTXHost::stop() {
  if (simu_thread_started_) {
    simuStop();
    pthread_join(simu_thread_, nullptr);
    simu_thread_started_ = false;
    LOGI("simu firmware thread joined");
  }
  if (initialized_) {
    initialized_ = false;
  }
  androidAudioDeinit();
  lcd_dirty_.store(false);
  lcd_has_frame_ = false;
}

bool EdgeTXHost::isRunning() { return simuIsRunning(); }

void EdgeTXHost::touchDown(int16_t x, int16_t y) { simuTouchDown(x, y); }

void EdgeTXHost::touchUp() { simuTouchUp(); }

void EdgeTXHost::refreshLcdLocked() {
  if (lcd_raw_size_ == 0 || lcd_raw_.empty()) return;
  if (!simuLcdBuf) return;

  const uint32_t copied = simuLcdCopy(lcd_raw_.data(), lcd_raw_size_);
  if (copied == 0 || copied > lcd_raw_size_) return;

  simuLcdFlushed();

  const size_t n = static_cast<size_t>(lcd_w_) * lcd_h_;
  if (lcd_argb_.size() < n) lcd_argb_.assign(n, 0);

  if (lcd_depth_ == 16) {
    const uint16_t* src = reinterpret_cast<const uint16_t*>(lcd_raw_.data());
    uint32_t* dst = lcd_argb_.data();
    for (size_t i = 0; i < n; ++i) {
      const uint16_t p = src[i];
      const uint32_t r =
          static_cast<uint32_t>(((p & 0xF800) >> 8) | ((p & 0xE000) >> 13));
      const uint32_t g =
          static_cast<uint32_t>(((p & 0x07E0) >> 3) | ((p & 0x0600) >> 9));
      const uint32_t b =
          static_cast<uint32_t>(((p & 0x001F) << 3) | ((p & 0x001C) >> 2));
      dst[i] = 0xFF000000u | (r << 16) | (g << 8) | b;
    }
  } else {
    for (size_t i = 0; i < n; ++i) lcd_argb_[i] = 0xFF002814u;
  }
  lcd_has_frame_ = true;
}

bool EdgeTXHost::pollLcdArgb(std::vector<uint32_t>& out) {
  if (!lcd_dirty_.exchange(false, std::memory_order_acq_rel)) return false;
  std::lock_guard<std::recursive_mutex> lock(mu_);
  if (!lcd_has_frame_ || lcd_argb_.empty()) return false;
  out = lcd_argb_;
  return true;
}
