package io.github.levitateing.etxandroid

import android.content.Context
import android.graphics.Color
import android.graphics.RectF
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.View.MeasureSpec
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import kotlin.math.max

/**
 * On-screen TX keys shown only while a Lua tool script or fullscreen Lua widget is active.
 * Maps to [EnumKeys] in radio/src/hal/key_driver.h.
 */
class LuaVirtualKeyBar(context: Context) : FrameLayout(context) {

    private val bar = LinearLayout(context).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER
        setBackgroundColor(0xCC1A1A1A.toInt())
        setPadding(dp(6), dp(6), dp(6), dp(6))
    }

    init {
        visibility = GONE
        isClickable = false
        addView(bar, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT))
    }

    fun bind(screen: EdgeTXScreenView) {
        if (bar.childCount > 0) return

        addKey(screen, "RTN", NativeSim.KEY_EXIT, longPress = true, hint = "长按退出")
        addKey(screen, "ENT", NativeSim.KEY_ENTER)
        // TX16-style radios use rotary encoder for up/down (EVT_VIRTUAL_PREV/NEXT).
        addRotaryKey(screen, "▲", -1)
        addRotaryKey(screen, "▼", 1)
        addKey(screen, "◀", NativeSim.KEY_PAGEUP)
        addKey(screen, "▶", NativeSim.KEY_PAGEDN)
        addKey(screen, "PG-", NativeSim.KEY_PAGEUP)
        addKey(screen, "PG+", NativeSim.KEY_PAGEDN)
    }

    fun updateLayout(dest: RectF) {
        if (visibility != VISIBLE || dest.isEmpty) return
        val barW = bar.measuredWidth
        val barH = bar.measuredHeight
        if (barW <= 0 || barH <= 0) {
            bar.measure(
                MeasureSpec.makeMeasureSpec(dest.width().toInt(), MeasureSpec.AT_MOST),
                MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)
            )
        }
        val w = if (bar.measuredWidth > 0) bar.measuredWidth else barW
        val h = if (bar.measuredHeight > 0) bar.measuredHeight else barH
        val left = dest.left + (dest.width() - w) / 2f
        val top = dest.bottom - h - dp(8)
        bar.x = left
        bar.y = max(dest.top + dp(4), top)
    }

    fun setLuaActive(active: Boolean) {
        visibility = if (active) VISIBLE else GONE
    }

    override fun onTouchEvent(event: MotionEvent): Boolean = false

    private fun addKey(
        screen: EdgeTXScreenView,
        label: String,
        key: Int,
        longPress: Boolean = false,
        hint: String? = null
    ) {
        val btn = TextView(context).apply {
            text = label
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            gravity = Gravity.CENTER
            setBackgroundColor(0xFF333333.toInt())
            minWidth = dp(44)
            minHeight = dp(40)
            setPadding(dp(8), dp(6), dp(8), dp(6))
            contentDescription = hint ?: label
        }

        val lp = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            marginStart = dp(4)
            marginEnd = dp(4)
        }
        bar.addView(btn, lp)

        if (longPress) {
            attachLongPressKey(btn, screen, key)
        } else {
            btn.setOnClickListener { screen.sendKeyPulse(key) }
        }
    }

    private fun addRotaryKey(screen: EdgeTXScreenView, label: String, steps: Int) {
        val btn = TextView(context).apply {
            text = label
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            gravity = Gravity.CENTER
            setBackgroundColor(0xFF333333.toInt())
            minWidth = dp(44)
            minHeight = dp(40)
            setPadding(dp(8), dp(6), dp(8), dp(6))
            contentDescription = label
        }
        val lp = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            marginStart = dp(4)
            marginEnd = dp(4)
        }
        bar.addView(btn, lp)
        btn.setOnClickListener { screen.sendRotaryPulse(steps) }
    }

    private fun attachLongPressKey(view: View, screen: EdgeTXScreenView, key: Int) {
        var longFired = false
        val longRunnable = Runnable {
            longFired = true
            screen.sendKeyPulse(key, NativeSim.KEY_LONG_MS)
        }
        view.setOnTouchListener { v, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    longFired = false
                    v.postDelayed(longRunnable, NativeSim.KEY_LONG_MS)
                    true
                }
                MotionEvent.ACTION_UP -> {
                    v.removeCallbacks(longRunnable)
                    if (!longFired) {
                        screen.sendKeyPulse(key)
                    }
                    true
                }
                MotionEvent.ACTION_CANCEL -> {
                    v.removeCallbacks(longRunnable)
                    true
                }
                else -> false
            }
        }
    }

    private fun dp(value: Int): Int {
        val density = resources.displayMetrics.density
        return (value * density + 0.5f).toInt()
    }
}
