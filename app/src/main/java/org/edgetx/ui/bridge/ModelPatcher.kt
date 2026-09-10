package org.edgetx.ui.bridge

/**
 * Diff two ModelData blobs into PATCH regions (coalesced).
 */
object ModelPatcher {
    private const val GAP_MERGE = 8
    private const val MAX_REGIONS = 64

    fun diff(baseline: ByteArray, current: ByteArray): List<AndroidBridgeProto.PatchRegion>? {
        if (baseline.size != current.size) return null
        val raw = ArrayList<IntRange>()
        var i = 0
        val n = current.size
        while (i < n) {
            if (baseline[i] == current[i]) {
                i++
                continue
            }
            val start = i
            while (i < n && baseline[i] != current[i]) i++
            raw.add(start until i)
        }
        if (raw.isEmpty()) return emptyList()

        // Merge close ranges
        val merged = ArrayList<IntRange>()
        var cur = raw[0]
        for (k in 1 until raw.size) {
            val next = raw[k]
            if (next.first - cur.last <= GAP_MERGE) {
                cur = cur.first until next.last
            } else {
                merged.add(cur)
                cur = next
            }
        }
        merged.add(cur)

        if (merged.size > MAX_REGIONS) return null // caller should PUT full

        return merged.map { r ->
            AndroidBridgeProto.PatchRegion(
                offset = r.first,
                data = current.copyOfRange(r.first, r.last + 1),
            )
        }
    }

    fun patchPayloadBytes(regions: List<AndroidBridgeProto.PatchRegion>): Int {
        var size = 2
        for (r in regions) size += 4 + r.data.size
        return size
    }
}
