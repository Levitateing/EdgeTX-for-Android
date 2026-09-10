package io.github.levitateing.etxandroid

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF
import android.util.AttributeSet
import android.view.MotionEvent
import android.view.View
import java.util.TimeZone
import kotlin.concurrent.thread
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Fullscreen native EdgeTX LCD view (app-private SD under Android/data/io.github.levitateing.etxandroid/EdgeTX).
 */
class EdgeTXScreenView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : View(context, attrs) {

    enum class ScaleMode {
        FILL,
        FIT
    }

    var scaleMode: ScaleMode = ScaleMode.FIT

    private val filterPaint = Paint(Paint.FILTER_BITMAP_FLAG).apply {
        isFilterBitmap = true
    }
    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        textSize = 42f
    }

    private var lcdBitmap: Bitmap? = null
    private var lcdW = 800
    private var lcdH = 480
    private var ready = false
    val isReady: Boolean
        get() = ready

    /** Letterboxed destination rect for the firmware LCD (screen coordinates). */
    fun getLcdDestRect(): RectF = RectF(destRect)
    private var status = "Starting EdgeTX…"
    private var running = true

    private val destRect = RectF()
    private val srcRect = Rect()

    private val frameRunnable = object : Runnable {
        override fun run() {
            if (!running) return
            if (ready) {
                // Ignore stale exit flag until firmware has been started this session.
                if (NativeSim.nativeIsRunning() && NativeSim.nativeHostExitRequested()) {
                    running = false
                    removeCallbacks(this)
                    (context as? MainActivity)?.onFirmwarePowerOff()
                    return
                }
                val pixels = NativeSim.nativePollLcdArgb()
                if (pixels != null) {
                    updateLcdPixels(pixels)
                    invalidate()
                }
            } else {
                invalidate()
            }
            postDelayed(this, 16)
        }
    }

    init {
        setBackgroundColor(Color.BLACK)
        keepScreenOn = true
        setLayerType(LAYER_TYPE_HARDWARE, filterPaint)
        thread(name = "edgetx-boot", isDaemon = true) {
            boot()
        }
        post(frameRunnable)
    }

    private fun boot() {
        try {
            val sdRoot = SdCardStore.resolveRoot(context)
            // Settings live under the same SD tree (normal EdgeTX layout).
            val settingsRoot = sdRoot
            postStatus("SD: ${sdRoot.absolutePath}")
            NativeSim.nativeSetStoragePaths(sdRoot.absolutePath, settingsRoot.absolutePath)

            postStatus("Native firmware 800×480")
            postStatus("Initializing…")
            if (!NativeSim.nativeInit()) {
                postStatus("simuInit failed: ${NativeSim.nativeLastError()}")
                return
            }
            postStatus("Mounting SD…")
            if (!NativeSim.nativePrepareStorage()) {
                postStatus("storage failed: ${NativeSim.nativeLastError()}")
                return
            }
            if (!SdCardStore.hasRadioSettings(sdRoot)) {
                NativeSim.nativeCreateDefaults()
            }
            val info = NativeSim.nativeLcdInfo()
            lcdW = info[0].coerceAtLeast(1)
            lcdH = info[1].coerceAtLeast(1)
            post {
                scaleMode = ScaleMode.FIT
                ensureLcdBitmap()
                layoutDestRect(width, height)
                invalidate()
            }
            postStatus("Starting…")
            val offset = TimeZone.getDefault().rawOffset / 1000
            // tests=true: normal splash / hello / checks (SD contents optional)
            if (!NativeSim.nativeStart(true, offset)) {
                postStatus("simuStart failed: ${NativeSim.nativeLastError()}")
                return
            }
            ready = true
            postStatus("")
            post {
                (context as? MainActivity)?.onSimulatorReady()
            }
        } catch (t: Throwable) {
            postStatus("Error: ${t.message}")
        }
    }

    private fun postStatus(msg: String) {
        post {
            status = msg
            invalidate()
        }
    }

    private fun ensureLcdBitmap() {
        val existing = lcdBitmap
        if (existing != null && existing.width == lcdW && existing.height == lcdH) return
        existing?.recycle()
        lcdBitmap = Bitmap.createBitmap(lcdW, lcdH, Bitmap.Config.ARGB_8888)
        srcRect.set(0, 0, lcdW, lcdH)
    }

    private fun updateLcdPixels(pixels: IntArray) {
        ensureLcdBitmap()
        val bmp = lcdBitmap ?: return
        val n = lcdW * lcdH
        if (pixels.size < n) return
        bmp.setPixels(pixels, 0, lcdW, 0, 0, lcdW, lcdH)
    }

    private fun layoutDestRect(vw: Int, vh: Int) {
        if (vw <= 0 || vh <= 0 || lcdW <= 0 || lcdH <= 0) return
        when (scaleMode) {
            ScaleMode.FILL -> {
                destRect.set(0f, 0f, vw.toFloat(), vh.toFloat())
            }
            ScaleMode.FIT -> {
                val scale = min(vw.toFloat() / lcdW, vh.toFloat() / lcdH)
                val dw = lcdW * scale
                val dh = lcdH * scale
                val left = (vw - dw) / 2f
                val top = (vh - dh) / 2f
                destRect.set(left, top, left + dw, top + dh)
            }
        }
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        layoutDestRect(w, h)
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val src = lcdBitmap
        if (src != null && ready && !destRect.isEmpty) {
            canvas.drawBitmap(src, srcRect, destRect, filterPaint)
        }
        if (status.isNotEmpty()) {
            canvas.drawText(status, 40f, height / 2f, textPaint)
        }
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (!ready) return true
        val dw = destRect.width()
        val dh = destRect.height()
        if (dw < 1f || dh < 1f) return true

        val lx = ((event.x - destRect.left) / dw * lcdW).roundToInt().coerceIn(0, lcdW - 1)
        val ly = ((event.y - destRect.top) / dh * lcdH).roundToInt().coerceIn(0, lcdH - 1)

        if (scaleMode == ScaleMode.FIT) {
            if (event.x < destRect.left || event.x > destRect.right ||
                event.y < destRect.top || event.y > destRect.bottom
            ) {
                if (event.actionMasked == MotionEvent.ACTION_UP ||
                    event.actionMasked == MotionEvent.ACTION_CANCEL
                ) {
                    NativeSim.nativeTouch(lx, ly, false)
                }
                return true
            }
        }

        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_MOVE -> {
                NativeSim.nativeTouch(lx, ly, true)
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                NativeSim.nativeTouch(lx, ly, false)
            }
        }
        return true
    }

    fun sendKey(key: Int, down: Boolean) {
        if (!ready) return
        NativeSim.nativeSetKey(key, down)
    }

    fun sendKeyPulse(key: Int, holdMs: Long = NativeSim.KEY_SHORT_MS) {
        if (!ready) return
        NativeSim.nativeSetKey(key, true)
        postDelayed({ NativeSim.nativeSetKey(key, false) }, holdMs)
    }

    fun sendRotaryPulse(steps: Int) {
        if (!ready) return
        NativeSim.nativeRotaryEncoderEvent(steps)
    }

    /** Short EXIT — delivered to Lua scripts as EVT_VIRTUAL_EXIT / back navigation. */
    fun sendExitKey() {
        if (!ready) return
        sendKeyPulse(NativeSim.KEY_EXIT)
    }

    /** Long EXIT (~350 ms) — exits standalone Lua tools and fullscreen Lua widgets. */
    fun sendLongExitKey() {
        sendKeyPulse(NativeSim.KEY_EXIT, NativeSim.KEY_LONG_MS)
    }

    fun shutdown() {
        running = false
        removeCallbacks(frameRunnable)
        try {
            NativeSim.nativeStop()
        } catch (_: Throwable) {
        }
        lcdBitmap?.recycle()
        lcdBitmap = null
    }
}
