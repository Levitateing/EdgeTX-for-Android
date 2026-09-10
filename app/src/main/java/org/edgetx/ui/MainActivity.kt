package org.edgetx.ui

import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.TextView
import androidx.activity.OnBackPressedCallback
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import org.edgetx.ui.bridge.AndroidBridgeProto
import org.edgetx.ui.bridge.ModelPatcher
import org.edgetx.ui.bridge.UsbBridgeManager

/**
 * Hosts the native EdgeTX LCD using app-private SD storage under
 * `/sdcard/Android/data/org.edgetx.ui/EdgeTX`.
 *
 * Also hosts USB Bridge (OTG → radio CDC) for MCU link bring-up.
 */
class MainActivity : AppCompatActivity() {
    private var screen: EdgeTXScreenView? = null
    private var luaKeys: LuaVirtualKeyBar? = null
    private var bridgeStatus: TextView? = null
    private var usbBridge: UsbBridgeManager? = null
    private var luaPollRunning = false

    private val luaPollRunnable = object : Runnable {
        override fun run() {
            val view = screen
            val keys = luaKeys
            if (view != null && keys != null && view.isReady) {
                val active = NativeSim.nativeIsLuaScriptActive()
                keys.setLuaActive(active)
                if (active) {
                    keys.updateLayout(view.getLcdDestRect())
                }
            }
            if (luaPollRunning) {
                screen?.postDelayed(this, 150)
            }
        }
    }

    private val backCallback = object : OnBackPressedCallback(true) {
        override fun handleOnBackPressed() {
            screen?.sendExitKey()
        }
    }

    private var lastInputUiMs = 0L
    private var linkInfo = ""
    private var pongOk = false
    private var statusExtra = ""
    private var mcuModelSize = 0L
    private var putModelScheduled = false
    private var awaitingModelSync = false
    private var modelBaseline: ByteArray? = null
    private var lastChannels: ShortArray? = null
    private var lastModelName = ""
    private var lastStickMode = -1
    private var lastTemplateSetup = -1
    private var lastMcuModelCrc = 0L
    private var patchInFlight = false

    private val patchPollRunnable = object : Runnable {
        override fun run() {
            maybeSendModelPatch()
            maybePushRadioFlight()
            if (usbBridge?.isLinked() == true) {
                window.decorView.postDelayed(this, PATCH_POLL_MS)
            }
        }
    }

    private val bridgeListener = object : UsbBridgeManager.Listener {
        override fun onBridgeLog(message: String) {
            runOnUiThread { bridgeStatus?.text = "USB: $message" }
        }

        override fun onBridgeLinked(hello: AndroidBridgeProto.HelloPayload) {
            mcuModelSize = hello.modelDataSize
            applyRadioSettingsFromMcu(hello.stickMode, hello.templateSetup)
            runOnUiThread {
                pongOk = false
                statusExtra = ""
                awaitingModelSync = true
                putModelScheduled = false
                linkInfo =
                    "USB LINKED board=${hello.boardId} hw=${hello.hwId} " +
                        "md=${hello.modelDataSize} mode=${hello.stickMode + 1} " +
                        "tmpl=${hello.templateSetup} caps=0x${hello.caps.toString(16)}"
                paintBanner()
                usbBridge?.ping()
                // MCU owns calib / hardware radio settings — pull first.
                if ((hello.caps and AndroidBridgeProto.CAP_GET_RADIO.toLong()) != 0L) {
                    usbBridge?.getRadio()
                }
                // Fallback if STATUS stream is slow/missing.
                window.decorView.postDelayed({
                    if (awaitingModelSync) {
                        awaitingModelSync = false
                        scheduleModelSyncByCrc(lastMcuModelCrc)
                    }
                }, 2500)
                window.decorView.removeCallbacks(patchPollRunnable)
                window.decorView.postDelayed(patchPollRunnable, PATCH_POLL_MS)
            }
        }

        override fun onBridgeDisconnected() {
            putModelScheduled = false
            awaitingModelSync = false
            patchInFlight = false
            modelBaseline = null
            mcuModelSize = 0
            lastStickMode = -1
            lastTemplateSetup = -1
            lastMcuModelCrc = 0
            window.decorView.removeCallbacks(patchPollRunnable)
            runCatching { NativeSim.nativeSetPwrPressed(false) }
            runOnUiThread {
                linkInfo = ""
                pongOk = false
                statusExtra = ""
                bridgeStatus?.text = "USB: disconnected"
            }
        }

        override fun onBridgePong() {
            runOnUiThread {
                pongOk = true
                paintBanner()
            }
        }

        override fun onBridgeInput(input: AndroidBridgeProto.InputPayload) {
            applyInputToSimu(input)
            val now = System.currentTimeMillis()
            if (now - lastInputUiMs < 250) return
            lastInputUiMs = now
            val s = input.sticks
            val ch = lastChannels
            val chTxt = if (ch != null && ch.size >= 4) {
                " CH=[${ch[0]},${ch[1]},${ch[2]},${ch[3]}]"
            } else ""
            runOnUiThread {
                statusExtra =
                    "IN s=[${s[0]},${s[1]},${s[2]},${s[3]}] k=0x${input.keys.toString(16)}$chTxt"
                paintBanner()
            }
        }

        override fun onBridgeChannels(ch: AndroidBridgeProto.ChPayload) {
            lastChannels = ch.channels
        }

        override fun onBridgeStatus(st: AndroidBridgeProto.StatusPayload) {
            lastModelName = st.modelName
            lastMcuModelCrc = st.modelCrc
            applyRadioSettingsFromMcu(st.stickMode, st.templateSetup)
            if (awaitingModelSync) {
                awaitingModelSync = false
                scheduleModelSyncByCrc(st.modelCrc)
            }
            runOnUiThread { paintBanner() }
        }

        override fun onBridgePutModelAck(ack: AndroidBridgeProto.PutModelAck) {
            statusExtra = when (ack.status) {
                AndroidBridgeProto.PUT_OK -> {
                    modelBaseline = NativeSim.nativeGetModelData()?.copyOf()
                    "PUT_MODEL ok md=${ack.modelDataSize}"
                }
                AndroidBridgeProto.PUT_SIZE_MISMATCH ->
                    "PUT_MODEL size mismatch mcu=${ack.modelDataSize}"
                AndroidBridgeProto.PUT_BUSY -> "PUT_MODEL busy"
                else -> "PUT_MODEL fail status=${ack.status}"
            }
            runOnUiThread { paintBanner() }
        }

        override fun onBridgePatchModelAck(ack: AndroidBridgeProto.PutModelAck) {
            patchInFlight = false
            statusExtra = when (ack.status) {
                AndroidBridgeProto.PUT_OK -> {
                    modelBaseline = NativeSim.nativeGetModelData()?.copyOf()
                    "PATCH ok"
                }
                else -> "PATCH fail status=${ack.status}"
            }
            runOnUiThread { paintBanner() }
        }

        override fun onBridgeModelData(modelBytes: ByteArray) {
            val ok = runCatching { NativeSim.nativeSetModelData(modelBytes) }.getOrDefault(false)
            if (ok) {
                modelBaseline = modelBytes.copyOf()
                statusExtra = "GET_MODEL applied ${modelBytes.size}B"
            } else {
                statusExtra = "GET_MODEL apply failed size=${modelBytes.size}"
            }
            runOnUiThread { paintBanner() }
        }

        override fun onBridgePutRadioAck(ack: AndroidBridgeProto.PutModelAck) {
            statusExtra = when (ack.status) {
                AndroidBridgeProto.PUT_OK -> "PUT_RADIO ok rd=${ack.modelDataSize}"
                AndroidBridgeProto.PUT_SIZE_MISMATCH ->
                    "PUT_RADIO size mismatch mcu=${ack.modelDataSize}"
                else -> "PUT_RADIO fail status=${ack.status}"
            }
            runOnUiThread { paintBanner() }
        }

        override fun onBridgeRadioData(radioBytes: ByteArray) {
            val ok = runCatching { NativeSim.nativeSetRadioData(radioBytes) }.getOrDefault(false)
            if (ok) {
                // Refresh cached stick/template from applied RadioData.
                lastStickMode = -1
                lastTemplateSetup = -1
                val sm = runCatching { NativeSim.nativeGetStickMode() }.getOrDefault(0)
                val ts = runCatching { NativeSim.nativeGetTemplateSetup() }.getOrDefault(0)
                applyRadioSettingsFromMcu(sm, ts)
                statusExtra = "GET_RADIO applied ${radioBytes.size}B"
            } else {
                statusExtra = "GET_RADIO apply failed size=${radioBytes.size}"
            }
            runOnUiThread { paintBanner() }
        }
    }

    private fun paintBanner() {
        if (linkInfo.isEmpty()) return
        val name = if (lastModelName.isNotEmpty()) " model=$lastModelName" else ""
        val pong = if (pongOk) " | PONG ok" else ""
        val extra = if (statusExtra.isNotEmpty()) " | $statusExtra" else ""
        bridgeStatus?.text = "$linkInfo$name$pong$extra"
    }

    private fun applyRadioSettingsFromMcu(stickMode: Int, templateSetup: Int) {
        val sm = stickMode and 3
        val ts = templateSetup and 0xFF
        if (sm != lastStickMode) {
            lastStickMode = sm
            runCatching { NativeSim.nativeSetStickMode(sm) }
        }
        if (ts != lastTemplateSetup) {
            lastTemplateSetup = ts
            runCatching { NativeSim.nativeSetTemplateSetup(ts) }
        }
    }

    private fun maybePushRadioFlight() {
        val bridge = usbBridge ?: return
        if (!bridge.isLinked()) return
        if (lastStickMode < 0) return
        val sm = runCatching { NativeSim.nativeGetStickMode() }.getOrDefault(lastStickMode)
        val ts = runCatching { NativeSim.nativeGetTemplateSetup() }.getOrDefault(lastTemplateSetup)
        if (sm == lastStickMode && ts == lastTemplateSetup) return
        if (bridge.putRadioFlight(sm, ts)) {
            lastStickMode = sm
            lastTemplateSetup = ts
        }
    }

    private fun applyInputToSimu(input: AndroidBridgeProto.InputPayload) {
        // analogs[0..3]=sticks, [4..]=FLEX pots in TX16S order: S1,6POS,S2,LS,RS,...
        val analogs = ShortArray(4 + AndroidBridgeProto.INPUT_POTS) { 2048 }
        for (i in 0 until 4) analogs[i] = AndroidBridgeProto.resxToAdc(input.sticks[i])
        for (i in input.pots.indices) {
            if (4 + i < analogs.size) {
                analogs[4 + i] = AndroidBridgeProto.resxToAdc(input.pots[i])
            }
        }
        val switches = ByteArray(16)
        for (i in 0 until 16) {
            val pos = ((input.switches shr (i * 2)) and 3L).toInt()
            switches[i] = when (pos) {
                0 -> -1
                1 -> 0
                else -> 1
            }.toByte()
        }
        runCatching {
            NativeSim.nativeApplyBridgeInput(
                analogs,
                switches,
                input.keys,
                input.trimKeys,
                input.trims,
            )
            if (input.rotencDelta != 0) {
                NativeSim.nativeRotaryEncoderEvent(input.rotencDelta)
            }
            NativeSim.nativeSetPwrPressed(input.pwr)
        }
    }

    private fun scheduleModelSyncByCrc(mcuCrc: Long) {
        if (putModelScheduled) return
        putModelScheduled = true
        window.decorView.postDelayed({
            val bridge = usbBridge ?: return@postDelayed
            val bytes = NativeSim.nativeGetModelData()
            if (bytes == null) {
                statusExtra = "model sync skip (simu not ready)"
                paintBanner()
                return@postDelayed
            }
            if (mcuModelSize > 0 && bytes.size.toLong() != mcuModelSize) {
                statusExtra = "PUT abort app=${bytes.size} mcu=$mcuModelSize"
                paintBanner()
                return@postDelayed
            }
            val localCrc = runCatching { NativeSim.nativeGetModelCrc32() }
                .getOrElse { AndroidBridgeProto.crc32Bytes(bytes) }
            if (mcuCrc != 0L && localCrc == mcuCrc) {
                modelBaseline = bytes.copyOf()
                statusExtra = "model CRC match — skip PUT"
                paintBanner()
                return@postDelayed
            }
            statusExtra = "model CRC differ app=0x${localCrc.toString(16)} mcu=0x${mcuCrc.toString(16)}"
            paintBanner()
            bridge.putModel(bytes, mcuModelSize)
        }, 400)
    }

    private fun maybeSendModelPatch() {
        if (patchInFlight) return
        val bridge = usbBridge ?: return
        if (!bridge.isLinked()) return
        val baseline = modelBaseline ?: return
        val current = NativeSim.nativeGetModelData() ?: return
        if (current.size != baseline.size) return
        val regions = ModelPatcher.diff(baseline, current) ?: run {
            bridge.putModel(current, mcuModelSize)
            return
        }
        if (regions.isEmpty()) return
        val bytes = ModelPatcher.patchPayloadBytes(regions)
        if (bytes > AndroidBridgeProto.MAX_PAYLOAD) {
            bridge.putModel(current, mcuModelSize)
            return
        }
        patchInFlight = true
        if (!bridge.patchModel(regions)) patchInFlight = false
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        volumeControlStream = android.media.AudioManager.STREAM_MUSIC
        onBackPressedDispatcher.addCallback(this, backCallback)

        WindowCompat.setDecorFitsSystemWindows(window, false)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        WindowInsetsControllerCompat(window, window.decorView).let { c ->
            c.hide(WindowInsetsCompat.Type.systemBars())
            c.systemBarsBehavior =
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        }

        if (!SdCardStore.ensureSeeded(this)) {
            showStorageError(
                "无法初始化 EdgeTX 存储\n" +
                    "路径: Android/data/org.edgetx.ui/EdgeTX\n\n" +
                    "请检查手机存储空间是否充足。"
            )
            return
        }
        startSimulator()
        startUsbBridge()
    }

    private fun startUsbBridge() {
        usbBridge = UsbBridgeManager(this, bridgeListener).also { it.start() }
        // Handle cold-start via USB_DEVICE_ATTACHED launcher intent.
        intent?.let { usbBridge?.onUsbDeviceIntent(it) }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        usbBridge?.onUsbDeviceIntent(intent)
    }

    private fun showStorageError(message: String) {
        val tv = TextView(this).apply {
            text = message
            setTextColor(0xFFFFFFFF.toInt())
            textSize = 16f
            gravity = Gravity.CENTER
            setPadding(48, 48, 48, 48)
        }
        setContentView(
            FrameLayout(this).apply {
                setBackgroundColor(0xFF000000.toInt())
                addView(
                    tv,
                    FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.MATCH_PARENT,
                        FrameLayout.LayoutParams.WRAP_CONTENT,
                        Gravity.CENTER
                    )
                )
            }
        )
    }

    override fun onDestroy() {
        luaPollRunning = false
        screen?.removeCallbacks(luaPollRunnable)
        window.decorView.removeCallbacks(patchPollRunnable)
        usbBridge?.stop()
        usbBridge = null
        EdgeTXHostSync.detach()
        screen?.shutdown()
        screen = null
        luaKeys = null
        super.onDestroy()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            window.decorView.systemUiVisibility =
                (View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                    or View.SYSTEM_UI_FLAG_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                    or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION)
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        when (event.keyCode) {
            KeyEvent.KEYCODE_VOLUME_UP, KeyEvent.KEYCODE_VOLUME_DOWN -> {
                return super.dispatchKeyEvent(event)
            }
        }
        return super.dispatchKeyEvent(event)
    }

    fun onSimulatorReady() {
        EdgeTXHostSync.attach(this)
    }

    /** Called when TX power-off sequence completes in firmware. */
    fun onFirmwarePowerOff() {
        luaPollRunning = false
        screen?.removeCallbacks(luaPollRunnable)
        window.decorView.removeCallbacks(patchPollRunnable)
        usbBridge?.stop()
        usbBridge = null
        EdgeTXHostSync.detach()
        runCatching { screen?.shutdown() }
        screen = null
        finishAndRemoveTask()
        // Ensure native statics (pwr_check_state, exit flag) die with the process.
        android.os.Process.killProcess(android.os.Process.myPid())
    }

    private fun startSimulator() {
        if (screen != null) return
        val root = FrameLayout(this)
        val view = EdgeTXScreenView(this)
        val keys = LuaVirtualKeyBar(this).apply { bind(view) }
        val status = TextView(this).apply {
            text = "USB: starting…"
            setTextColor(Color.YELLOW)
            textSize = 12f
            setBackgroundColor(0x66000000)
            setPadding(16, 8, 16, 8)
        }
        root.addView(view, FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT)
        root.addView(
            keys,
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        )
        root.addView(
            status,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.TOP or Gravity.START
            )
        )
        screen = view
        luaKeys = keys
        bridgeStatus = status
        setContentView(root)
        luaPollRunning = true
        view.post(luaPollRunnable)
    }

    companion object {
        private const val PATCH_POLL_MS = 1000L
    }
}
