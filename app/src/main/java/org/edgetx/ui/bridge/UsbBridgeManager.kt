package org.edgetx.ui.bridge

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.hoho.android.usbserial.driver.UsbSerialPort
import com.hoho.android.usbserial.driver.UsbSerialProber
import com.hoho.android.usbserial.util.SerialInputOutputManager
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/**
 * USB CDC host for Android Bridge (phone OTG → radio device).
 * Streams INPUT/CH/STATUS from MCU; PUT/PATCH/GET model + radio sync.
 *
 * Writes never run on the UI thread. Attach/detach + poll reconnect so the
 * App can start before VCP is ready without freezing.
 */
class UsbBridgeManager(
    private val context: Context,
    private val listener: Listener,
) : SerialInputOutputManager.Listener {

    interface Listener {
        fun onBridgeLog(message: String)
        fun onBridgeLinked(hello: AndroidBridgeProto.HelloPayload)
        fun onBridgeDisconnected()
        fun onBridgePong()
        fun onBridgeInput(input: AndroidBridgeProto.InputPayload)
        fun onBridgeChannels(ch: AndroidBridgeProto.ChPayload)
        fun onBridgeStatus(st: AndroidBridgeProto.StatusPayload)
        fun onBridgePutModelAck(ack: AndroidBridgeProto.PutModelAck)
        fun onBridgePatchModelAck(ack: AndroidBridgeProto.PutModelAck)
        fun onBridgeModelData(modelBytes: ByteArray)
        fun onBridgePutRadioAck(ack: AndroidBridgeProto.PutModelAck)
        fun onBridgeRadioData(radioBytes: ByteArray)
    }

    private val usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager
    private val parser = AndroidBridgeProto.Parser()
    private val seq = AtomicInteger(1)
    /** Dedicated to SerialInputOutputManager read loop — do not queue writes here. */
    private val readExecutor = Executors.newSingleThreadExecutor()
    /** All CDC writes (HELLO / PUT / PATCH / PING). */
    private val writeExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val linked = AtomicBoolean(false)
    private val writeLock = Any()
    private val stopped = AtomicBoolean(false)

    @Volatile private var port: UsbSerialPort? = null
    private var ioManager: SerialInputOutputManager? = null
    private var permissionReceiverRegistered = false
    private var usbLifecycleRegistered = false
    private var helloAttempts = 0

    private val helloRetryRunnable = object : Runnable {
        override fun run() {
            if (stopped.get() || port == null || linked.get()) return
            if (helloAttempts >= MAX_HELLO_ATTEMPTS) {
                listener.onBridgeLog("HELLO timeout — will keep retrying when USB is ready")
                helloAttempts = 0
                // Close half-open port so reconnect poll can re-open after VCP comes up.
                closePort()
                scheduleReconnect()
                return
            }
            sendHello()
            mainHandler.postDelayed(this, HELLO_RETRY_MS)
        }
    }

    private val reconnectRunnable = object : Runnable {
        override fun run() {
            if (stopped.get()) return
            if (port == null && !linked.get()) {
                connectFirstCdc()
            }
            mainHandler.postDelayed(this, RECONNECT_POLL_MS)
        }
    }

    private val permissionReceiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context?, intent: Intent?) {
            if (intent?.action != ACTION_USB_PERMISSION) return
            val device: UsbDevice? = if (Build.VERSION.SDK_INT >= 33) {
                intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
            }
            val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
            if (granted && device != null) {
                openDevice(device)
            } else {
                listener.onBridgeLog("USB permission denied")
            }
        }
    }

    private val usbLifecycleReceiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context?, intent: Intent?) {
            when (intent?.action) {
                UsbManager.ACTION_USB_DEVICE_ATTACHED -> {
                    listener.onBridgeLog("USB attached")
                    mainHandler.post { connectFirstCdc() }
                }
                UsbManager.ACTION_USB_DEVICE_DETACHED -> {
                    listener.onBridgeLog("USB detached")
                    closePort()
                    listener.onBridgeDisconnected()
                }
            }
        }
    }

    fun start() {
        stopped.set(false)
        if (!permissionReceiverRegistered) {
            val filter = IntentFilter(ACTION_USB_PERMISSION)
            if (Build.VERSION.SDK_INT >= 33) {
                context.registerReceiver(permissionReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                context.registerReceiver(permissionReceiver, filter)
            }
            permissionReceiverRegistered = true
        }
        if (!usbLifecycleRegistered) {
            val filter = IntentFilter().apply {
                addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
                addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
            }
            if (Build.VERSION.SDK_INT >= 33) {
                context.registerReceiver(usbLifecycleReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                context.registerReceiver(usbLifecycleReceiver, filter)
            }
            usbLifecycleRegistered = true
        }
        connectFirstCdc()
        scheduleReconnect()
    }

    fun stop() {
        stopped.set(true)
        mainHandler.removeCallbacks(helloRetryRunnable)
        mainHandler.removeCallbacks(reconnectRunnable)
        closePort()
        if (permissionReceiverRegistered) {
            runCatching { context.unregisterReceiver(permissionReceiver) }
            permissionReceiverRegistered = false
        }
        if (usbLifecycleRegistered) {
            runCatching { context.unregisterReceiver(usbLifecycleReceiver) }
            usbLifecycleRegistered = false
        }
        listener.onBridgeDisconnected()
    }

    /** Call when Activity receives USB_DEVICE_ATTACHED via onNewIntent. */
    fun onUsbDeviceIntent(intent: Intent?) {
        if (intent?.action == UsbManager.ACTION_USB_DEVICE_ATTACHED) {
            listener.onBridgeLog("USB intent attach")
            connectFirstCdc()
        }
    }

    fun ping() {
        val frame = AndroidBridgeProto.encodePing(seq.getAndIncrement())
        enqueueWrite(frame, WRITE_TIMEOUT_MS) { ok ->
            if (!ok) listener.onBridgeLog("ping write failed")
        }
    }

    /**
     * Push full ModelData blob to MCU. [modelBytes] must equal MCU HELLO modeldata_size.
     * @return false if not linked / size reject; true if write was queued
     */
    fun putModel(modelBytes: ByteArray, expectedMcuSize: Long): Boolean {
        if (port == null || !linked.get()) {
            listener.onBridgeLog("PUT_MODEL: not linked")
            return false
        }
        if (expectedMcuSize > 0 && modelBytes.size.toLong() != expectedMcuSize) {
            listener.onBridgeLog(
                "PUT_MODEL: size mismatch app=${modelBytes.size} mcu=$expectedMcuSize"
            )
            return false
        }
        if (modelBytes.size > AndroidBridgeProto.MAX_PAYLOAD) {
            listener.onBridgeLog("PUT_MODEL: payload too large ${modelBytes.size}")
            return false
        }
        val frame = AndroidBridgeProto.encodePutModel(seq.getAndIncrement(), modelBytes)
        enqueueWrite(frame, PUT_WRITE_TIMEOUT_MS) { ok ->
            if (ok) listener.onBridgeLog("PUT_MODEL sent ${modelBytes.size} bytes")
            else listener.onBridgeLog("PUT_MODEL write failed")
        }
        return true
    }

    fun patchModel(regions: List<AndroidBridgeProto.PatchRegion>): Boolean {
        if (port == null || !linked.get()) {
            listener.onBridgeLog("PATCH_MODEL: not linked")
            return false
        }
        if (regions.isEmpty()) return true
        val bytes = ModelPatcher.patchPayloadBytes(regions)
        if (bytes > AndroidBridgeProto.MAX_PAYLOAD) {
            listener.onBridgeLog("PATCH_MODEL: too large ($bytes), use PUT")
            return false
        }
        val frame = AndroidBridgeProto.encodePatchModel(seq.getAndIncrement(), regions)
        enqueueWrite(frame, PUT_WRITE_TIMEOUT_MS) { ok ->
            if (ok) listener.onBridgeLog("PATCH_MODEL sent ${regions.size} regions ($bytes B)")
            else listener.onBridgeLog("PATCH_MODEL write failed")
        }
        return true
    }

    fun putRadioFlight(stickMode: Int, templateSetup: Int): Boolean {
        if (port == null || !linked.get()) return false
        val frame = AndroidBridgeProto.encodePutRadioFlight(
            seq.getAndIncrement(), stickMode, templateSetup
        )
        enqueueWrite(frame, WRITE_TIMEOUT_MS) { ok ->
            if (!ok) listener.onBridgeLog("PUT_RADIO_FLIGHT failed")
        }
        return true
    }

    fun getModel(): Boolean {
        if (port == null || !linked.get()) {
            listener.onBridgeLog("GET_MODEL: not linked")
            return false
        }
        val frame = AndroidBridgeProto.encodeGetModel(seq.getAndIncrement())
        enqueueWrite(frame, WRITE_TIMEOUT_MS) { ok ->
            if (ok) listener.onBridgeLog("GET_MODEL sent")
            else listener.onBridgeLog("GET_MODEL write failed")
        }
        return true
    }

    fun putRadio(radioBytes: ByteArray, expectedMcuSize: Long): Boolean {
        if (port == null || !linked.get()) {
            listener.onBridgeLog("PUT_RADIO: not linked")
            return false
        }
        if (expectedMcuSize > 0 && radioBytes.size.toLong() != expectedMcuSize) {
            listener.onBridgeLog(
                "PUT_RADIO: size mismatch app=${radioBytes.size} mcu=$expectedMcuSize"
            )
            return false
        }
        if (radioBytes.size > AndroidBridgeProto.MAX_PAYLOAD) {
            listener.onBridgeLog("PUT_RADIO: payload too large ${radioBytes.size}")
            return false
        }
        val frame = AndroidBridgeProto.encodePutRadio(seq.getAndIncrement(), radioBytes)
        enqueueWrite(frame, PUT_WRITE_TIMEOUT_MS) { ok ->
            if (ok) listener.onBridgeLog("PUT_RADIO sent ${radioBytes.size} bytes")
            else listener.onBridgeLog("PUT_RADIO write failed")
        }
        return true
    }

    fun getRadio(): Boolean {
        if (port == null || !linked.get()) {
            listener.onBridgeLog("GET_RADIO: not linked")
            return false
        }
        val frame = AndroidBridgeProto.encodeGetRadio(seq.getAndIncrement())
        enqueueWrite(frame, WRITE_TIMEOUT_MS) { ok ->
            if (ok) listener.onBridgeLog("GET_RADIO sent")
            else listener.onBridgeLog("GET_RADIO write failed")
        }
        return true
    }

    fun isLinked(): Boolean = linked.get()

    fun connectFirstCdc() {
        if (stopped.get()) return
        if (port != null) return
        val drivers = UsbSerialProber.getDefaultProber().findAllDrivers(usbManager)
        if (drivers.isEmpty()) {
            val devices = usbManager.deviceList.values
            val cdc = devices.firstOrNull { hasCdcInterface(it) }
            if (cdc == null) {
                // Quiet when nothing plugged — reconnect poll will try again.
                return
            }
            requestOrOpen(cdc)
            return
        }
        val device = drivers[0].device
        requestOrOpen(device)
    }

    private fun scheduleReconnect() {
        mainHandler.removeCallbacks(reconnectRunnable)
        mainHandler.postDelayed(reconnectRunnable, RECONNECT_POLL_MS)
    }

    private fun enqueueWrite(
        frame: ByteArray,
        timeoutMs: Int,
        onDone: ((Boolean) -> Unit)? = null,
    ) {
        writeExecutor.execute {
            val ok = writeFrameSync(frame, timeoutMs)
            if (onDone != null) {
                mainHandler.post { onDone(ok) }
            }
        }
    }

    private fun writeFrameSync(frame: ByteArray, timeoutMs: Int): Boolean {
        val p = port ?: return false
        return runCatching {
            synchronized(writeLock) {
                p.write(frame, timeoutMs)
            }
            true
        }.getOrElse {
            Log.w(TAG, "CDC write failed: ${it.message}")
            false
        }
    }

    private fun requestOrOpen(device: UsbDevice) {
        if (usbManager.hasPermission(device)) {
            openDevice(device)
        } else {
            listener.onBridgeLog("Requesting USB permission for ${device.deviceName}")
            val flags = if (Build.VERSION.SDK_INT >= 31) {
                PendingIntent.FLAG_MUTABLE
            } else {
                0
            }
            val pi = PendingIntent.getBroadcast(
                context,
                0,
                Intent(ACTION_USB_PERMISSION),
                flags,
            )
            usbManager.requestPermission(device, pi)
        }
    }

    private fun openDevice(device: UsbDevice) {
        if (stopped.get()) return
        closePort()
        linked.set(false)
        helloAttempts = 0
        val drivers = UsbSerialProber.getDefaultProber().findAllDrivers(usbManager)
            .filter { it.device.deviceId == device.deviceId && it.device.vendorId == device.vendorId }
        val driver = drivers.firstOrNull()
        if (driver == null) {
            listener.onBridgeLog("No serial driver for ${device.deviceName}")
            return
        }
        val connection = usbManager.openDevice(device)
        if (connection == null) {
            listener.onBridgeLog("openDevice failed")
            return
        }
        val serialPort = driver.ports[0]
        runCatching {
            serialPort.open(connection)
            serialPort.setParameters(115200, 8, UsbSerialPort.STOPBITS_1, UsbSerialPort.PARITY_NONE)
            serialPort.dtr = true
            serialPort.rts = true
        }.onFailure {
            listener.onBridgeLog("port open failed: ${it.message}")
            runCatching { serialPort.close() }
            return
        }
        port = serialPort
        ioManager = SerialInputOutputManager(serialPort, this).also {
            readExecutor.submit(it)
        }
        listener.onBridgeLog("CDC open: vid=${device.vendorId} pid=${device.productId}")
        // Small delay then HELLO with retries — radio may still be claiming VCP RX.
        mainHandler.postDelayed({
            sendHello()
            mainHandler.postDelayed(helloRetryRunnable, HELLO_RETRY_MS)
        }, HELLO_INITIAL_DELAY_MS)
    }

    private fun sendHello() {
        if (port == null || linked.get()) return
        helloAttempts++
        val localSize = runCatching {
            org.edgetx.ui.NativeSim.nativeGetModelDataSize().toLong()
        }.getOrDefault(0L)
        val stickMode = runCatching {
            org.edgetx.ui.NativeSim.nativeGetStickMode()
        }.getOrDefault(0)
        val templateSetup = runCatching {
            org.edgetx.ui.NativeSim.nativeGetTemplateSetup()
        }.getOrDefault(0)
        val frame = AndroidBridgeProto.encodeHello(
            seq.getAndIncrement(), localSize, stickMode, templateSetup
        )
        enqueueWrite(frame, WRITE_TIMEOUT_MS) { ok ->
            if (ok) listener.onBridgeLog("HELLO sent (#$helloAttempts)")
            else listener.onBridgeLog("HELLO failed (#$helloAttempts)")
        }
    }

    private fun stopHelloRetry() {
        mainHandler.removeCallbacks(helloRetryRunnable)
    }

    private fun closePort() {
        stopHelloRetry()
        linked.set(false)
        ioManager?.listener = null
        ioManager?.stop()
        ioManager = null
        runCatching { port?.close() }
        port = null
    }

    override fun onNewData(data: ByteArray) {
        val frames = parser.push(data)
        for (frame in frames) {
            when (frame.cmd) {
                AndroidBridgeProto.CMD_HELLO_ACK -> {
                    val hello = AndroidBridgeProto.parseHelloPayload(frame.payload)
                    if (hello != null) {
                        linked.set(true)
                        stopHelloRetry()
                        Log.i(TAG, "HELLO_ACK board=${hello.boardId} hw=${hello.hwId}")
                        listener.onBridgeLinked(hello)
                    } else {
                        listener.onBridgeLog("HELLO_ACK parse failed")
                    }
                }
                AndroidBridgeProto.CMD_PONG -> listener.onBridgePong()
                AndroidBridgeProto.CMD_INPUT_STREAM -> {
                    val input = AndroidBridgeProto.parseInputPayload(frame.payload)
                    if (input != null) listener.onBridgeInput(input)
                }
                AndroidBridgeProto.CMD_CH_STREAM -> {
                    val ch = AndroidBridgeProto.parseChPayload(frame.payload)
                    if (ch != null) listener.onBridgeChannels(ch)
                }
                AndroidBridgeProto.CMD_STATUS -> {
                    val st = AndroidBridgeProto.parseStatusPayload(frame.payload)
                    if (st != null) listener.onBridgeStatus(st)
                }
                AndroidBridgeProto.CMD_PUT_MODEL_ACK -> {
                    val ack = AndroidBridgeProto.parsePutModelAck(frame.payload)
                    if (ack != null) listener.onBridgePutModelAck(ack)
                    else listener.onBridgeLog("PUT_MODEL_ACK parse failed")
                }
                AndroidBridgeProto.CMD_PATCH_MODEL_ACK -> {
                    val ack = AndroidBridgeProto.parsePutModelAck(frame.payload)
                    if (ack != null) listener.onBridgePatchModelAck(ack)
                    else listener.onBridgeLog("PATCH_MODEL_ACK parse failed")
                }
                AndroidBridgeProto.CMD_PUT_RADIO_FLIGHT_ACK -> {
                    val ack = AndroidBridgeProto.parsePutModelAck(frame.payload)
                    if (ack != null && ack.status == AndroidBridgeProto.PUT_OK) {
                        listener.onBridgeLog("RADIO_FLIGHT ok")
                    }
                }
                AndroidBridgeProto.CMD_MODEL_DATA -> {
                    listener.onBridgeModelData(frame.payload)
                }
                AndroidBridgeProto.CMD_PUT_RADIO_ACK -> {
                    val ack = AndroidBridgeProto.parsePutModelAck(frame.payload)
                    if (ack != null) listener.onBridgePutRadioAck(ack)
                    else listener.onBridgeLog("PUT_RADIO_ACK parse failed")
                }
                AndroidBridgeProto.CMD_RADIO_DATA -> {
                    listener.onBridgeRadioData(frame.payload)
                }
                AndroidBridgeProto.CMD_NACK -> listener.onBridgeLog("NACK cmd payload")
                else -> listener.onBridgeLog("RX cmd=0x${frame.cmd.toString(16)} len=${frame.payload.size}")
            }
        }
    }

    override fun onRunError(e: Exception?) {
        listener.onBridgeLog("CDC IO error: ${e?.message}")
        closePort()
        listener.onBridgeDisconnected()
        scheduleReconnect()
    }

    private fun hasCdcInterface(device: UsbDevice): Boolean {
        for (i in 0 until device.interfaceCount) {
            if (device.getInterface(i).interfaceClass == UsbConstants.USB_CLASS_CDC_DATA ||
                device.getInterface(i).interfaceClass == UsbConstants.USB_CLASS_COMM
            ) {
                return true
            }
        }
        return false
    }

    companion object {
        private const val TAG = "UsbBridge"
        private const val ACTION_USB_PERMISSION = "org.edgetx.ui.USB_PERMISSION"
        private const val WRITE_TIMEOUT_MS = 1500
        private const val PUT_WRITE_TIMEOUT_MS = 5000
        private const val HELLO_INITIAL_DELAY_MS = 300L
        private const val HELLO_RETRY_MS = 1000L
        private const val MAX_HELLO_ATTEMPTS = 8
        private const val RECONNECT_POLL_MS = 2000L
    }
}
