package io.github.levitateing.etxandroid.bridge

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.zip.CRC32

/**
 * Wire codec for [android_bridge_proto.h]. Little-endian frames over USB CDC.
 */
object AndroidBridgeProto {
    const val VERSION: Byte = 1
    private val MAGIC = byteArrayOf('E'.code.toByte(), 'T'.code.toByte(), 'X'.code.toByte(), 'B'.code.toByte())

    const val HEADER_SIZE = 13
    const val CRC_SIZE = 4
    const val MAX_PAYLOAD = 8192

    const val INPUT_POTS = 10
    const val INPUT_TRIMS = 8
    const val CH_MAX = 32

    const val CMD_HELLO: Int = 0x0001
    const val CMD_HELLO_ACK: Int = 0x0002
    const val CMD_PING: Int = 0x0003
    const val CMD_PONG: Int = 0x0004
    const val CMD_GET_STATUS: Int = 0x0005
    const val CMD_STATUS: Int = 0x0006
    const val CMD_INPUT_STREAM: Int = 0x0010
    const val CMD_CH_STREAM: Int = 0x0011
    const val CMD_PUT_MODEL: Int = 0x0020
    const val CMD_PUT_MODEL_ACK: Int = 0x0021
    const val CMD_PATCH_MODEL: Int = 0x0022
    const val CMD_PATCH_MODEL_ACK: Int = 0x0023
    const val CMD_PUT_RADIO_FLIGHT: Int = 0x0024
    const val CMD_PUT_RADIO_FLIGHT_ACK: Int = 0x0025
    const val CMD_GET_MODEL: Int = 0x0026
    const val CMD_MODEL_DATA: Int = 0x0027
    const val CMD_PUT_RADIO: Int = 0x0028
    const val CMD_PUT_RADIO_ACK: Int = 0x0029
    const val CMD_GET_RADIO: Int = 0x002A
    const val CMD_RADIO_DATA: Int = 0x002B
    const val CMD_NACK: Int = 0x00FF

    const val PUT_OK = 0
    const val PUT_SIZE_MISMATCH = 1
    const val PUT_BUSY = 2
    const val PUT_BAD = 3

    const val CAP_INPUT_STREAM = 1 shl 0
    const val CAP_CH_STREAM = 1 shl 1
    const val CAP_PUT_MODEL = 1 shl 2
    const val CAP_PATCH_MODEL = 1 shl 3
    const val CAP_RADIO_FLIGHT = 1 shl 4
    const val CAP_GET_MODEL = 1 shl 5
    const val CAP_PUT_RADIO = 1 shl 6
    const val CAP_GET_RADIO = 1 shl 7

    data class Frame(val cmd: Int, val seq: Int, val payload: ByteArray)

    data class HelloPayload(
        val protoVersion: Int,
        val caps: Long,
        val modelDataSize: Long,
        val radioFlightSize: Long,
        val boardId: String,
        val hwId: String,
        val stickMode: Int, // 0..3 = Mode 1..4
        val templateSetup: Int,
    )

    /** Matches AndroidBridgeInputPayload. */
    data class InputPayload(
        val timestampMs: Long,
        val sticks: ShortArray, // 4 RESX
        val pots: ShortArray,   // 8 RESX
        val trims: ShortArray,  // 8
        val switches: Long,
        val keys: Int,
        val trimKeys: Int,
        val rotencDelta: Int,
        val pwr: Boolean,
    )

    data class ChPayload(
        val timestampMs: Long,
        val channels: ShortArray,
    )

    data class StatusPayload(
        val modelCrc: Long,
        val radioFlightCrc: Long,
        val linkOk: Boolean,
        val usbModeOk: Boolean,
        val stickMode: Int,
        val templateSetup: Int,
        val modelName: String,
    )

    data class PutModelAck(
        val status: Int,
        val modelDataSize: Long,
    )

    data class PatchRegion(val offset: Int, val data: ByteArray)

    fun encodeFrame(cmd: Int, seq: Int, payload: ByteArray = ByteArray(0)): ByteArray {
        require(payload.size <= MAX_PAYLOAD)
        val hdr = ByteBuffer.allocate(HEADER_SIZE).order(ByteOrder.LITTLE_ENDIAN)
        hdr.put(MAGIC)
        hdr.put(VERSION)
        hdr.putShort(cmd.toShort())
        hdr.putShort(seq.toShort())
        hdr.putInt(payload.size)
        val header = hdr.array()
        val crc = crc32(header, payload)
        return header + payload + intLe(crc)
    }

    fun encodeHello(
        seq: Int,
        modelDataSize: Long = 0,
        stickMode: Int = 0,
        templateSetup: Int = 0,
    ): ByteArray {
        // proto + caps + sizes + board + hw + stick + template + pad = 49
        val raw = ByteArray(1 + 4 + 4 + 4 + 16 + 16 + 4)
        raw[0] = VERSION
        val caps = (CAP_INPUT_STREAM or CAP_CH_STREAM or CAP_PUT_MODEL or
            CAP_PATCH_MODEL or CAP_RADIO_FLIGHT or CAP_GET_MODEL or
            CAP_PUT_RADIO or CAP_GET_RADIO).toLong()
        writeU32(raw, 1, caps)
        writeU32(raw, 5, modelDataSize)
        writeU32(raw, 9, 4) // radio_flight_size (stickMode/templateSetup)
        "android".toByteArray(Charsets.US_ASCII).copyInto(raw, 13, 0, minOf(7, 15))
        "phone".toByteArray(Charsets.US_ASCII).copyInto(raw, 29, 0, minOf(5, 15))
        raw[45] = (stickMode and 3).toByte()
        raw[46] = (templateSetup and 0xFF).toByte()
        return encodeFrame(CMD_HELLO, seq, raw)
    }

    fun encodePutRadioFlight(seq: Int, stickMode: Int, templateSetup: Int): ByteArray {
        val raw = byteArrayOf(
            (stickMode and 3).toByte(),
            (templateSetup and 0xFF).toByte(),
            0, 0,
        )
        return encodeFrame(CMD_PUT_RADIO_FLIGHT, seq, raw)
    }

    fun encodePing(seq: Int, token: ByteArray = byteArrayOf(1)): ByteArray =
        encodeFrame(CMD_PING, seq, token)

    fun encodePutModel(seq: Int, modelBytes: ByteArray): ByteArray =
        encodeFrame(CMD_PUT_MODEL, seq, modelBytes)

    fun encodeGetModel(seq: Int): ByteArray = encodeFrame(CMD_GET_MODEL, seq)

    fun encodePutRadio(seq: Int, radioBytes: ByteArray): ByteArray =
        encodeFrame(CMD_PUT_RADIO, seq, radioBytes)

    fun encodeGetRadio(seq: Int): ByteArray = encodeFrame(CMD_GET_RADIO, seq)

    fun encodePatchModel(seq: Int, regions: List<PatchRegion>): ByteArray {
        require(regions.isNotEmpty())
        var size = 2
        for (r in regions) size += 4 + r.data.size
        require(size <= MAX_PAYLOAD)
        val raw = ByteArray(size)
        raw[0] = (regions.size and 0xFF).toByte()
        raw[1] = ((regions.size shr 8) and 0xFF).toByte()
        var o = 2
        for (r in regions) {
            raw[o++] = (r.offset and 0xFF).toByte()
            raw[o++] = ((r.offset shr 8) and 0xFF).toByte()
            raw[o++] = (r.data.size and 0xFF).toByte()
            raw[o++] = ((r.data.size shr 8) and 0xFF).toByte()
            r.data.copyInto(raw, o)
            o += r.data.size
        }
        return encodeFrame(CMD_PATCH_MODEL, seq, raw)
    }

    class Parser {
        private val buf = ArrayList<Byte>(256)

        fun push(data: ByteArray, offset: Int = 0, length: Int = data.size): List<Frame> {
            for (i in offset until offset + length) buf.add(data[i])
            val out = ArrayList<Frame>()
            while (true) {
                val frame = tryPop() ?: break
                out.add(frame)
            }
            return out
        }

        private fun tryPop(): Frame? {
            while (buf.size >= HEADER_SIZE) {
                if (buf[0] != MAGIC[0] || buf[1] != MAGIC[1] || buf[2] != MAGIC[2] || buf[3] != MAGIC[3]) {
                    buf.removeAt(0)
                    continue
                }
                if (buf[4] != VERSION) {
                    buf.removeAt(0)
                    continue
                }
                val cmd = u16(buf, 5)
                val seq = u16(buf, 7)
                val plen = u32(buf, 9).toInt()
                if (plen < 0 || plen > MAX_PAYLOAD) {
                    buf.removeAt(0)
                    continue
                }
                val frameLen = HEADER_SIZE + plen + CRC_SIZE
                if (buf.size < frameLen) return null

                val header = ByteArray(HEADER_SIZE) { buf[it] }
                val payload = ByteArray(plen) { buf[HEADER_SIZE + it] }
                val got = u32(buf, HEADER_SIZE + plen)
                val expect = crc32(header, payload)
                repeat(frameLen) { buf.removeAt(0) }
                if (got != expect) continue
                return Frame(cmd, seq, payload)
            }
            return null
        }
    }

    fun parseHelloPayload(payload: ByteArray): HelloPayload? {
        if (payload.size < 1 + 4 + 4 + 4 + 16 + 16) return null
        val stick = if (payload.size >= 46) payload[45].toInt() and 3 else 0
        val tmpl = if (payload.size >= 47) payload[46].toInt() and 0xFF else 0
        return HelloPayload(
            protoVersion = payload[0].toInt() and 0xFF,
            caps = u32(payload, 1),
            modelDataSize = u32(payload, 5),
            radioFlightSize = u32(payload, 9),
            boardId = cstring(payload, 13, 16),
            hwId = cstring(payload, 29, 16),
            stickMode = stick,
            templateSetup = tmpl,
        )
    }

    fun parseInputPayload(payload: ByteArray): InputPayload? {
        // ts4 + sticks8 + pots20 + trims16 + sw4 + keys2 + trimKeys2 + rotenc2 + pwr1 + res1 = 60
        if (payload.size < 60) return null
        val bb = ByteBuffer.wrap(payload).order(ByteOrder.LITTLE_ENDIAN)
        val ts = bb.int.toLong() and 0xFFFFFFFFL
        val sticks = ShortArray(4) { bb.short }
        val pots = ShortArray(INPUT_POTS) { bb.short }
        val trims = ShortArray(INPUT_TRIMS) { bb.short }
        val switches = bb.int.toLong() and 0xFFFFFFFFL
        val keys = bb.short.toInt() and 0xFFFF
        val trimKeys = bb.short.toInt() and 0xFFFF
        val rotencDelta = bb.short.toInt()
        val pwr = bb.get().toInt() != 0
        return InputPayload(ts, sticks, pots, trims, switches, keys, trimKeys, rotencDelta, pwr)
    }

    fun parseChPayload(payload: ByteArray): ChPayload? {
        if (payload.size < 8) return null
        val bb = ByteBuffer.wrap(payload).order(ByteOrder.LITTLE_ENDIAN)
        val ts = bb.int.toLong() and 0xFFFFFFFFL
        val count = bb.get().toInt() and 0xFF
        bb.get(); bb.get(); bb.get() // reserved
        if (count > CH_MAX || payload.size < 8 + count * 2) return null
        val channels = ShortArray(count) { bb.short }
        return ChPayload(ts, channels)
    }

    fun parseStatusPayload(payload: ByteArray): StatusPayload? {
        if (payload.size < 28) return null
        return StatusPayload(
            modelCrc = u32(payload, 0),
            radioFlightCrc = u32(payload, 4),
            linkOk = payload[8] != 0.toByte(),
            usbModeOk = payload[9] != 0.toByte(),
            stickMode = payload[10].toInt() and 3,
            templateSetup = payload[11].toInt() and 0xFF,
            modelName = cstring(payload, 12, 16),
        )
    }

    fun parsePutModelAck(payload: ByteArray): PutModelAck? {
        if (payload.size < 8) return null
        return PutModelAck(
            status = payload[0].toInt() and 0xFF,
            modelDataSize = u32(payload, 4),
        )
    }

    /** RESX (-1024..1024) → ADC (0..4096, center 2048). */
    fun resxToAdc(resx: Short): Short {
        var v = resx.toInt()
        if (v < -1024) v = -1024
        if (v > 1024) v = 1024
        return ((v + 1024) * 2).toShort()
    }

    /** IEEE CRC32 over bytes — matches MCU bridge model_crc. */
    fun crc32Bytes(data: ByteArray): Long {
        val c = CRC32()
        c.update(data)
        return c.value
    }

    private fun crc32(header: ByteArray, payload: ByteArray): Long {
        val c = CRC32()
        c.update(header)
        if (payload.isNotEmpty()) c.update(payload)
        return c.value
    }

    private fun intLe(v: Long): ByteArray =
        byteArrayOf(
            (v and 0xFF).toByte(),
            ((v shr 8) and 0xFF).toByte(),
            ((v shr 16) and 0xFF).toByte(),
            ((v shr 24) and 0xFF).toByte(),
        )

    private fun writeU32(dst: ByteArray, off: Int, v: Long) {
        dst[off] = (v and 0xFF).toByte()
        dst[off + 1] = ((v shr 8) and 0xFF).toByte()
        dst[off + 2] = ((v shr 16) and 0xFF).toByte()
        dst[off + 3] = ((v shr 24) and 0xFF).toByte()
    }

    private fun u16(buf: List<Byte>, off: Int): Int =
        (buf[off].toInt() and 0xFF) or ((buf[off + 1].toInt() and 0xFF) shl 8)

    private fun u32(buf: List<Byte>, off: Int): Long =
        (buf[off].toInt() and 0xFF).toLong() or
            ((buf[off + 1].toInt() and 0xFF).toLong() shl 8) or
            ((buf[off + 2].toInt() and 0xFF).toLong() shl 16) or
            ((buf[off + 3].toInt() and 0xFF).toLong() shl 24)

    private fun u32(buf: ByteArray, off: Int): Long =
        (buf[off].toInt() and 0xFF).toLong() or
            ((buf[off + 1].toInt() and 0xFF).toLong() shl 8) or
            ((buf[off + 2].toInt() and 0xFF).toLong() shl 16) or
            ((buf[off + 3].toInt() and 0xFF).toLong() shl 24)

    private fun cstring(buf: ByteArray, off: Int, max: Int): String {
        var end = off
        val limit = off + max
        while (end < limit && buf[end] != 0.toByte()) end++
        return String(buf, off, end - off, Charsets.US_ASCII)
    }
}
