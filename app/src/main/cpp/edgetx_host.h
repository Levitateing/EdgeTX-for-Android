#pragma once

#include <atomic>
#include <cstdint>
#include <mutex>
#include <pthread.h>
#include <string>
#include <vector>

// Android host for native EdgeTX SIMU (simulib ABI — no WASM/WAMR).
class EdgeTXHost {
 public:
  static EdgeTXHost& instance();

  void setStoragePaths(const std::string& sdPath, const std::string& settingsPath);

  bool init(std::string* err);
  bool prepareStorage(std::string* err);
  bool start(bool tests, int32_t utcOffset, std::string* err);
  void stop();
  bool isRunning();

  void touchDown(int16_t x, int16_t y);
  void touchUp();

  uint32_t lcdWidth() const { return lcd_w_; }
  uint32_t lcdHeight() const { return lcd_h_; }
  uint32_t lcdDepth() const { return lcd_depth_; }

  const std::string& lastError() const { return last_error_; }

  bool pollLcdArgb(std::vector<uint32_t>& out);

  int16_t getAnalog(uint8_t idx);
  /** Write host analog (ADC 0..4096, center 2048). */
  void setAnalog(uint8_t idx, int16_t adcValue);
  void setBattery(uint16_t voltage10mV, bool plugged, bool charging);
  bool hasBattery() const { return battery_valid_.load(std::memory_order_relaxed); }
  uint16_t batteryVoltage10mV() const {
    return battery_voltage_10mv_.load(std::memory_order_relaxed);
  }
  bool usbPlugged() const { return usb_plugged_.load(std::memory_order_relaxed); }
  bool usbCharging() const { return usb_charging_.load(std::memory_order_relaxed); }
  void trace(const char* text);
  void lcdNotify();

 private:
  EdgeTXHost() = default;
  ~EdgeTXHost();
  EdgeTXHost(const EdgeTXHost&) = delete;
  EdgeTXHost& operator=(const EdgeTXHost&) = delete;

  void refreshLcdLocked();

  // Recursive: LVGL flush may re-enter via simuLcdFlushed.
  std::recursive_mutex mu_;
  std::string sd_path_;
  std::string settings_path_;
  std::string last_error_;

  uint32_t lcd_w_ = 0;
  uint32_t lcd_h_ = 0;
  uint32_t lcd_depth_ = 0;
  uint32_t lcd_raw_size_ = 0;

  std::vector<uint8_t> lcd_raw_;
  std::vector<uint32_t> lcd_argb_;
  std::atomic<bool> lcd_dirty_{false};
  bool lcd_has_frame_ = false;
  bool initialized_ = false;

  int16_t analogs_[32] = {};
  bool analogs_inited_ = false;

  std::atomic<bool> battery_valid_{false};
  std::atomic<uint16_t> battery_voltage_10mv_{0};
  std::atomic<bool> usb_plugged_{false};
  std::atomic<bool> usb_charging_{false};

  pthread_t simu_thread_{};
  bool simu_thread_started_ = false;
};
