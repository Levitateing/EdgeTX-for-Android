#include <android/log.h>
#include <jni.h>

#include <algorithm>
#include <string>
#include <vector>

#include "edgetx_host.h"
#include "simulib.h"

// Defined in libedgetx_sim.a (BSS size 0x1deb). Do not include myeeprom.h here —
// jni_bridge has no radio/src include path / PCB defines.
extern char g_model;
static constexpr jint kAndroidModelDataSize = 0x1deb; /* sizeof(ModelData) RADIO_ANDROID */

extern "C" {

JNIEXPORT void JNICALL
Java_io_github_levitateing_etxandroid_NativeSim_nativeSetStoragePaths(JNIEnv* env, jclass,
                                                   jstring sdPath,
                                                   jstring settingsPath) {
  const char* sd = env->GetStringUTFChars(sdPath, nullptr);
  const char* st = env->GetStringUTFChars(settingsPath, nullptr);
  EdgeTXHost::instance().setStoragePaths(sd ? sd : "", st ? st : "");
  if (sd) env->ReleaseStringUTFChars(sdPath, sd);
  if (st) env->ReleaseStringUTFChars(settingsPath, st);
}

JNIEXPORT jboolean JNICALL
Java_io_github_levitateing_etxandroid_NativeSim_nativeLoadAsset(JNIEnv*, jclass, jobject,
                                             jstring) {
  // Native SIMU is linked into this .so — no WASM asset to load.
  return JNI_TRUE;
}

JNIEXPORT jboolean JNICALL
Java_io_github_levitateing_etxandroid_NativeSim_nativeInit(JNIEnv*, jclass) {
  std::string err;
  bool ok = EdgeTXHost::instance().init(&err);
  if (!ok) {
    __android_log_print(ANDROID_LOG_ERROR, "EdgeTXNative", "%s", err.c_str());
  }
  return ok ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL
Java_io_github_levitateing_etxandroid_NativeSim_nativePrepareStorage(JNIEnv*, jclass) {
  std::string err;
  bool ok = EdgeTXHost::instance().prepareStorage(&err);
  if (!ok) {
    __android_log_print(ANDROID_LOG_ERROR, "EdgeTXNative", "%s", err.c_str());
  }
  return ok ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT void JNICALL
Java_io_github_levitateing_etxandroid_NativeSim_nativeCreateDefaults(JNIEnv*, jclass) {
  simuCreateDefaults();
}

JNIEXPORT jboolean JNICALL
Java_io_github_levitateing_etxandroid_NativeSim_nativeStart(JNIEnv*, jclass, jboolean tests,
                                         jint utcOffset) {
  std::string err;
  bool ok = EdgeTXHost::instance().start(tests, utcOffset, &err);
  if (!ok && !err.empty()) {
    __android_log_print(ANDROID_LOG_ERROR, "EdgeTXNative", "%s", err.c_str());
  }
  return ok ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jstring JNICALL
Java_io_github_levitateing_etxandroid_NativeSim_nativeLastError(JNIEnv* env, jclass) {
  const std::string& e = EdgeTXHost::instance().lastError();
  return env->NewStringUTF(e.c_str());
}

JNIEXPORT void JNICALL
Java_io_github_levitateing_etxandroid_NativeSim_nativeStop(JNIEnv*, jclass) {
  EdgeTXHost::instance().stop();
}

JNIEXPORT jboolean JNICALL
Java_io_github_levitateing_etxandroid_NativeSim_nativeIsRunning(JNIEnv*, jclass) {
  return EdgeTXHost::instance().isRunning() ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL
Java_io_github_levitateing_etxandroid_NativeSim_nativeHostExitRequested(JNIEnv*, jclass) {
  return simuHostExitRequested() ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT void JNICALL
Java_io_github_levitateing_etxandroid_NativeSim_nativeTouch(JNIEnv*, jclass, jint x, jint y,
                                         jboolean down) {
  if (down) {
    EdgeTXHost::instance().touchDown((int16_t)x, (int16_t)y);
  } else {
    EdgeTXHost::instance().touchUp();
  }
}

JNIEXPORT jintArray JNICALL
Java_io_github_levitateing_etxandroid_NativeSim_nativeLcdInfo(JNIEnv* env, jclass) {
  auto& h = EdgeTXHost::instance();
  jintArray arr = env->NewIntArray(3);
  jint vals[3] = {(jint)h.lcdWidth(), (jint)h.lcdHeight(), (jint)h.lcdDepth()};
  env->SetIntArrayRegion(arr, 0, 3, vals);
  return arr;
}

JNIEXPORT jintArray JNICALL
Java_io_github_levitateing_etxandroid_NativeSim_nativePollLcdArgb(JNIEnv* env, jclass) {
  static thread_local std::vector<uint32_t> argb;
  if (!EdgeTXHost::instance().pollLcdArgb(argb) || argb.empty()) {
    return nullptr;
  }
  jintArray out = env->NewIntArray((jsize)argb.size());
  if (!out) return nullptr;
  env->SetIntArrayRegion(out, 0, (jsize)argb.size(),
                         reinterpret_cast<const jint*>(argb.data()));
  return out;
}

JNIEXPORT void JNICALL
Java_io_github_levitateing_etxandroid_NativeSim_nativeSetKey(JNIEnv*, jclass, jint key,
                                          jboolean down) {
  simuSetKey(static_cast<uint8_t>(key), down == JNI_TRUE);
}

JNIEXPORT void JNICALL
Java_io_github_levitateing_etxandroid_NativeSim_nativeRotaryEncoderEvent(JNIEnv*, jclass,
                                                     jint steps) {
  simuRotaryEncoderEvent(static_cast<int32_t>(steps));
}

JNIEXPORT jboolean JNICALL
Java_io_github_levitateing_etxandroid_NativeSim_nativeIsLuaScriptActive(JNIEnv*, jclass) {
  return simuIsLuaScriptActive() ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jint JNICALL
Java_io_github_levitateing_etxandroid_NativeSim_nativeGetBacklightLevel(JNIEnv*, jclass) {
  return static_cast<jint>(simuGetBacklightLevel());
}

JNIEXPORT jint JNICALL
Java_io_github_levitateing_etxandroid_NativeSim_nativeGetSpeakerVolume(JNIEnv*, jclass) {
  return static_cast<jint>(simuAudioGetVolume());
}

JNIEXPORT void JNICALL
Java_io_github_levitateing_etxandroid_NativeSim_nativeSetSpeakerVolume(JNIEnv*, jclass,
                                                    jint level) {
  if (level < 0) level = 0;
  simuSetSpeakerVolume(static_cast<uint8_t>(level));
}

JNIEXPORT jint JNICALL
Java_io_github_levitateing_etxandroid_NativeSim_nativeGetVolumeMax(JNIEnv*, jclass) {
  return static_cast<jint>(simuGetVolumeMax());
}

JNIEXPORT jint JNICALL
Java_io_github_levitateing_etxandroid_NativeSim_nativeGetHaptic(JNIEnv*, jclass) {
  return static_cast<jint>(simuGetHaptic());
}

JNIEXPORT void JNICALL
Java_io_github_levitateing_etxandroid_NativeSim_nativeSetBattery(JNIEnv*, jclass, jint levelPct,
                                              jboolean plugged,
                                              jboolean charging) {
  const int pct = std::max(0, std::min(100, static_cast<int>(levelPct)));
  // Map phone % to g_vbat100mV so Radio Info bar colors match:
  //   <20% red, 20–40% orange, >40% green, >95% full bar.
  // Uses default TX16S vBatMin/vBatMax (70..86 in 0.1 V) and bar thresholds
  // W_BATT_FILL_GRN=12, W_BATT_FILL_ORA=5 on a 20 px-wide fill.
  int vbat100mV;
  if (pct > 95) {
    vbat100mV = 86;
  } else if (pct > 40) {
    vbat100mV = 80 + (pct - 41) * (86 - 80) / (95 - 41);
  } else if (pct >= 20) {
    vbat100mV = 74 + (pct - 20) * 48 / 20;  // 74.0 .. 78.8 (bars 5..11)
  } else {
    vbat100mV = 70 + pct * 4 / 20;  // 70.0 .. 73.8 (bars 0..4)
  }
  const uint16_t voltage10mV =
      static_cast<uint16_t>(std::max(0, vbat100mV * 10 - 5));
  EdgeTXHost::instance().setBattery(voltage10mV, plugged == JNI_TRUE,
                                    charging == JNI_TRUE);
}

JNIEXPORT jbyteArray JNICALL
Java_io_github_levitateing_etxandroid_NativeSim_nativeGetModelData(JNIEnv* env, jclass) {
  if (!EdgeTXHost::instance().isRunning()) return nullptr;
  jbyteArray out = env->NewByteArray(kAndroidModelDataSize);
  if (!out) return nullptr;
  env->SetByteArrayRegion(out, 0, kAndroidModelDataSize,
                          reinterpret_cast<const jbyte*>(&g_model));
  return out;
}

JNIEXPORT jboolean JNICALL
Java_io_github_levitateing_etxandroid_NativeSim_nativeSetModelData(JNIEnv* env, jclass,
                                                jbyteArray data) {
  if (!EdgeTXHost::instance().isRunning() || !data) return JNI_FALSE;
  const jsize n = env->GetArrayLength(data);
  if (n != kAndroidModelDataSize) return JNI_FALSE;
  jbyte* bytes = env->GetByteArrayElements(data, nullptr);
  if (!bytes) return JNI_FALSE;
  const bool ok = simuApplyModelData(reinterpret_cast<const uint8_t*>(bytes),
                                     static_cast<uint32_t>(n));
  env->ReleaseByteArrayElements(data, bytes, JNI_ABORT);
  return ok ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jint JNICALL
Java_io_github_levitateing_etxandroid_NativeSim_nativeGetModelDataSize(JNIEnv*, jclass) {
  return kAndroidModelDataSize;
}

JNIEXPORT jlong JNICALL
Java_io_github_levitateing_etxandroid_NativeSim_nativeGetModelCrc32(JNIEnv*, jclass) {
  if (!EdgeTXHost::instance().isRunning()) return 0;
  return static_cast<jlong>(simuModelCrc32()) & 0xFFFFFFFFLL;
}

JNIEXPORT jbyteArray JNICALL
Java_io_github_levitateing_etxandroid_NativeSim_nativeGetRadioData(JNIEnv* env, jclass) {
  if (!EdgeTXHost::instance().isRunning()) return nullptr;
  const uint32_t sz = simuGetRadioDataSize();
  jbyteArray out = env->NewByteArray(static_cast<jsize>(sz));
  if (!out) return nullptr;
  std::vector<uint8_t> buf(sz);
  if (!simuCopyRadioData(buf.data(), sz)) return nullptr;
  env->SetByteArrayRegion(out, 0, static_cast<jsize>(sz),
                          reinterpret_cast<const jbyte*>(buf.data()));
  return out;
}

JNIEXPORT jboolean JNICALL
Java_io_github_levitateing_etxandroid_NativeSim_nativeSetRadioData(JNIEnv* env, jclass,
                                                jbyteArray data) {
  if (!EdgeTXHost::instance().isRunning() || !data) return JNI_FALSE;
  const jsize n = env->GetArrayLength(data);
  if (n != static_cast<jsize>(simuGetRadioDataSize())) return JNI_FALSE;
  jbyte* bytes = env->GetByteArrayElements(data, nullptr);
  if (!bytes) return JNI_FALSE;
  const bool ok = simuApplyRadioData(reinterpret_cast<const uint8_t*>(bytes),
                                     static_cast<uint32_t>(n));
  env->ReleaseByteArrayElements(data, bytes, JNI_ABORT);
  return ok ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jint JNICALL
Java_io_github_levitateing_etxandroid_NativeSim_nativeGetRadioDataSize(JNIEnv*, jclass) {
  return static_cast<jint>(simuGetRadioDataSize());
}

JNIEXPORT jint JNICALL
Java_io_github_levitateing_etxandroid_NativeSim_nativeGetStickMode(JNIEnv*, jclass) {
  return static_cast<jint>(simuGetStickMode());
}

JNIEXPORT void JNICALL
Java_io_github_levitateing_etxandroid_NativeSim_nativeSetStickMode(JNIEnv*, jclass, jint mode) {
  simuSetStickMode(static_cast<uint8_t>(mode & 3));
}

JNIEXPORT jint JNICALL
Java_io_github_levitateing_etxandroid_NativeSim_nativeGetTemplateSetup(JNIEnv*, jclass) {
  return static_cast<jint>(simuGetTemplateSetup());
}

JNIEXPORT void JNICALL
Java_io_github_levitateing_etxandroid_NativeSim_nativeSetTemplateSetup(JNIEnv*, jclass, jint setup) {
  simuSetTemplateSetup(static_cast<uint8_t>(setup & 0xFF));
}

JNIEXPORT void JNICALL
Java_io_github_levitateing_etxandroid_NativeSim_nativeSetPwrPressed(JNIEnv*, jclass, jboolean pressed) {
  simuSetPwrPressed(pressed == JNI_TRUE);
}

JNIEXPORT void JNICALL
Java_io_github_levitateing_etxandroid_NativeSim_nativeApplyBridgeInput(
    JNIEnv* env, jclass, jshortArray analogsAdc, jbyteArray switchStates,
    jint keysMask, jint trimKeysMask, jshortArray trimValues) {
  auto& host = EdgeTXHost::instance();
  if (!host.isRunning()) return;

  if (analogsAdc) {
    const jsize n = env->GetArrayLength(analogsAdc);
    jshort* a = env->GetShortArrayElements(analogsAdc, nullptr);
    if (a) {
      for (jsize i = 0; i < n && i < 32; i++) {
        host.setAnalog(static_cast<uint8_t>(i), a[i]);
      }
      env->ReleaseShortArrayElements(analogsAdc, a, JNI_ABORT);
    }
  }

  if (switchStates) {
    const jsize n = env->GetArrayLength(switchStates);
    jbyte* s = env->GetByteArrayElements(switchStates, nullptr);
    if (s) {
      for (jsize i = 0; i < n && i < 16; i++) {
        simuSetSwitch(static_cast<uint8_t>(i), static_cast<int8_t>(s[i]));
      }
      env->ReleaseByteArrayElements(switchStates, s, JNI_ABORT);
    }
  }

  static uint32_t prev_keys = 0;
  const uint32_t keys = static_cast<uint32_t>(keysMask) & 0xFFFFu;
  const uint32_t changed = keys ^ prev_keys;
  for (int bit = 0; bit < 16; bit++) {
    if (changed & (1u << bit)) {
      simuSetKey(static_cast<uint8_t>(bit), (keys & (1u << bit)) != 0);
    }
  }
  prev_keys = keys;

  // Do NOT apply trim_keys — MCU already advances trim values; applying keys
  // here double-steps and races with absolute trim sync below.
  (void)trimKeysMask;

  if (trimValues) {
    const jsize n = env->GetArrayLength(trimValues);
    jshort* t = env->GetShortArrayElements(trimValues, nullptr);
    if (t) {
      for (jsize i = 0; i < n && i < 8; i++) {
        simuSetTrimValue(static_cast<uint8_t>(i), static_cast<int32_t>(t[i]));
      }
      env->ReleaseShortArrayElements(trimValues, t, JNI_ABORT);
    }
  }
}

}  // extern "C"
