package org.edgetx.ui

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioManager
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.appcompat.app.AppCompatActivity
import kotlin.math.roundToInt

/**
 * Keeps Android window brightness / media volume / vibration / battery in sync with EdgeTX.
 */
class EdgeTXHostSync private constructor(
    private val activity: AppCompatActivity
) {
    private val handler = Handler(Looper.getMainLooper())
    private val audio = activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val vibrator: Vibrator? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        val mgr = activity.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
        mgr.defaultVibrator
    } else {
        @Suppress("DEPRECATION")
        activity.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
    }

    private var running = false
    private var lastBacklight = -1
    private var lastFirmwareVolume = -1
    private var lastAndroidVolume = -1
    private var lastHaptic = 0
    private var lastBattPct = -1
    private var lastBattPlugged = false
    private var lastBattCharging = false
    private var syncingToAndroid = false
    private var syncingToFirmware = false

    private val tick = object : Runnable {
        override fun run() {
            if (!running) return
            pollBacklight()
            pollVolume()
            pollHaptic()
            pollBattery()
            handler.postDelayed(this, POLL_MS)
        }
    }

    private fun pollBacklight() {
        val level = NativeSim.nativeGetBacklightLevel().coerceIn(0, 100)
        if (level == lastBacklight) return
        lastBacklight = level
        val lp = activity.window.attributes
        lp.screenBrightness = level / 100f
        activity.window.attributes = lp
    }

    private fun pollVolume() {
        val fwMax = NativeSim.nativeGetVolumeMax().coerceAtLeast(1)
        val androidMax = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        if (androidMax <= 0) return

        val fwVol = NativeSim.nativeGetSpeakerVolume().coerceIn(0, fwMax)
        if (!syncingToAndroid && fwVol != lastFirmwareVolume) {
            lastFirmwareVolume = fwVol
            syncingToAndroid = true
            val androidVol = ((fwVol * androidMax) / fwMax.toFloat()).roundToInt()
                .coerceIn(0, androidMax)
            if (androidVol != audio.getStreamVolume(AudioManager.STREAM_MUSIC)) {
                audio.setStreamVolume(AudioManager.STREAM_MUSIC, androidVol, 0)
            }
            lastAndroidVolume = androidVol
            syncingToAndroid = false
            return
        }

        val androidVol = audio.getStreamVolume(AudioManager.STREAM_MUSIC)
        if (!syncingToFirmware && androidVol != lastAndroidVolume) {
            lastAndroidVolume = androidVol
            syncingToFirmware = true
            val mapped = ((androidVol * fwMax) / androidMax.toFloat()).roundToInt()
                .coerceIn(0, fwMax)
            if (mapped != fwVol) {
                NativeSim.nativeSetSpeakerVolume(mapped)
                lastFirmwareVolume = mapped
            }
            syncingToFirmware = false
        }
    }

    private fun pollHaptic() {
        val counter = NativeSim.nativeGetHaptic()
        if (counter == lastHaptic) return
        val delta = counter - lastHaptic
        lastHaptic = counter
        if (delta <= 0) return
        val vib = vibrator ?: return
        val ms = (25 * delta).coerceIn(15, 400).toLong()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vib.vibrate(VibrationEffect.createOneShot(ms, VibrationEffect.DEFAULT_AMPLITUDE))
        } else {
            @Suppress("DEPRECATION")
            vib.vibrate(ms)
        }
    }

    private fun pollBattery() {
        val intent = activity.registerReceiver(
            null,
            IntentFilter(Intent.ACTION_BATTERY_CHANGED)
        ) ?: return
        val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, 100)
        if (level < 0 || scale <= 0) return
        val pct = ((level * 100L) / scale).toInt().coerceIn(0, 100)
        val status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
        val plugged = intent.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) != 0
        val charging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
            (status == BatteryManager.BATTERY_STATUS_FULL && plugged)
        if (pct == lastBattPct && plugged == lastBattPlugged &&
            charging == lastBattCharging
        ) {
            return
        }
        lastBattPct = pct
        lastBattPlugged = plugged
        lastBattCharging = charging
        NativeSim.nativeSetBattery(pct, plugged, charging)
    }

    fun start() {
        if (running) return
        running = true
        lastBacklight = -1
        lastFirmwareVolume = -1
        lastAndroidVolume = audio.getStreamVolume(AudioManager.STREAM_MUSIC)
        lastHaptic = NativeSim.nativeGetHaptic()
        lastBattPct = -1
        lastBattPlugged = false
        lastBattCharging = false
        handler.post(tick)
    }

    fun stop() {
        running = false
        handler.removeCallbacks(tick)
    }

    companion object {
        private const val POLL_MS = 100L
        private var instance: EdgeTXHostSync? = null

        fun attach(activity: AppCompatActivity) {
            detach()
            instance = EdgeTXHostSync(activity).also { it.start() }
        }

        fun detach() {
            instance?.stop()
            instance = null
        }
    }
}
