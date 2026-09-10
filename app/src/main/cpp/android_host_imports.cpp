// Firmware → host imports for native SIMU (replaces WASM import stubs).
#include "android_audio.h"
#include "edgetx_host.h"

uint16_t simuGetAnalog(uint8_t idx) {
  return static_cast<uint16_t>(EdgeTXHost::instance().getAnalog(idx));
}

void simuQueueAudio(const uint8_t* buf, uint32_t len) {
  androidAudioQueue(buf, len);
}

int simuGetAudioBufferedMs() {
  return androidAudioBufferedMs();
}

int simuGetAudioHostAudibleMs() {
  return androidAudioHostAudibleMs();
}

void simuTrace(const char* text) {
  EdgeTXHost::instance().trace(text);
}

void simuLcdNotify() {
  EdgeTXHost::instance().lcdNotify();
}

void simuFlushAudio() {
  androidAudioFlush();
}

bool simuGetHostBattery(uint16_t* voltage10mV, bool* plugged, bool* charging) {
  auto& host = EdgeTXHost::instance();
  if (!host.hasBattery()) return false;
  if (voltage10mV) *voltage10mV = host.batteryVoltage10mV();
  if (plugged) *plugged = host.usbPlugged();
  if (charging) *charging = host.usbCharging();
  return true;
}

// simuAuxSerial* stubs live in simulib.cpp for native builds.
