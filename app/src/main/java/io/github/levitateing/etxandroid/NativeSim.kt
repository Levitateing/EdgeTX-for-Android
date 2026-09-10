package io.github.levitateing.etxandroid

import android.content.res.AssetManager

object NativeSim {
    init {
        System.loadLibrary("edgetx_native")
    }

    /** Matches [EnumKeys] in radio/src/hal/key_driver.h */
    const val KEY_MENU = 0
    const val KEY_EXIT = 1
    const val KEY_ENTER = 2
    const val KEY_PAGEUP = 3
    const val KEY_PAGEDN = 4
    const val KEY_UP = 5
    const val KEY_DOWN = 6
    const val KEY_LEFT = 7
    const val KEY_RIGHT = 8
    const val KEY_PLUS = 9
    const val KEY_MINUS = 10
    const val KEY_MODEL = 11
    const val KEY_TELE = 12
    const val KEY_SYS = 13

    /** EdgeTX long-press threshold is ~320 ms (keys.cpp KEY_LONG_DELAY). */
    const val KEY_LONG_MS = 350L
    const val KEY_SHORT_MS = 80L

    external fun nativeSetStoragePaths(sdPath: String, settingsPath: String)
    external fun nativeLoadAsset(assetManager: AssetManager, assetPath: String): Boolean
    external fun nativeInit(): Boolean
    external fun nativePrepareStorage(): Boolean
    external fun nativeCreateDefaults()
    external fun nativeStart(tests: Boolean, utcOffset: Int): Boolean
    external fun nativeLastError(): String
    external fun nativeStop()
    external fun nativeIsRunning(): Boolean
    /** Firmware completed power-off — host should close the Activity. */
    external fun nativeHostExitRequested(): Boolean
    external fun nativeTouch(x: Int, y: Int, down: Boolean)
    external fun nativeLcdInfo(): IntArray
    external fun nativePollLcdArgb(): IntArray?

    external fun nativeSetKey(key: Int, down: Boolean)
    /** Rotary encoder step(s); negative = up/prev, positive = down/next on TX16. */
    external fun nativeRotaryEncoderEvent(steps: Int)
    external fun nativeIsLuaScriptActive(): Boolean
    /** EdgeTX backlight level 0..100 (respects radio on/off brightness). */
    external fun nativeGetBacklightLevel(): Int
    external fun nativeGetSpeakerVolume(): Int
    external fun nativeSetSpeakerVolume(level: Int)
    external fun nativeGetVolumeMax(): Int
    external fun nativeGetHaptic(): Int
    /** levelPct 0..100; plugged/charging mirror Android BatteryManager. */
    external fun nativeSetBattery(levelPct: Int, plugged: Boolean, charging: Boolean)

    /** Raw bytes of current SIMU `g_model` (must match MCU sizeof(ModelData)). */
    external fun nativeGetModelData(): ByteArray?
    external fun nativeSetModelData(data: ByteArray): Boolean

    external fun nativeGetModelDataSize(): Int
    external fun nativeGetModelCrc32(): Long

    /** Raw bytes of current SIMU `g_eeGeneral` (RadioData, 1183 on ANDROID). */
    external fun nativeGetRadioData(): ByteArray?
    external fun nativeSetRadioData(data: ByteArray): Boolean
    external fun nativeGetRadioDataSize(): Int

    /** 0..3 = Mode 1..4 (g_eeGeneral.stickMode). */
    external fun nativeGetStickMode(): Int
    external fun nativeSetStickMode(mode: Int)
    external fun nativeGetTemplateSetup(): Int
    external fun nativeSetTemplateSetup(setup: Int)
    external fun nativeSetPwrPressed(pressed: Boolean)

    /**
     * Inject TX physical inputs into SIMU.
     * [analogsAdc] length ≤ 32, values 0..4096 (center 2048).
     * [switchStates] length ≤ 16, values -1=UP, 0=MID, +1=DOWN.
     * [keysMask] / [trimKeysMask] bitmasks matching EnumKeys / trim keys.
     * [trimValues] length ≤ 8, current trim axis values.
     */
    external fun nativeApplyBridgeInput(
        analogsAdc: ShortArray,
        switchStates: ByteArray,
        keysMask: Int,
        trimKeysMask: Int,
        trimValues: ShortArray,
    )
}
