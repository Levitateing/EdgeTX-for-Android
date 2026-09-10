package org.edgetx.ui

import android.content.Context
import android.util.Log
import java.io.File

/**
 * SD card root for the native FatFS layer.
 *
 * Target path: `/sdcard/Android/data/org.edgetx.ui/EdgeTX`
 *
 * Android 10+ blocks creating `Android/data/<package>/…` via a raw
 * [android.os.Environment.getExternalStorageDirectory] path. The package sandbox
 * must be opened first with [Context.getExternalFilesDir] (which also creates the
 * standard sibling `files/` directory — that is normal and required by the OS).
 */
object SdCardStore {
    private const val TAG = "EdgeTXSd"
    const val FOLDER_NAME = "EdgeTX"

    /**
     * Returns `/…/Android/data/org.edgetx.ui/EdgeTX`, creating the package sandbox
     * if needed. Returns null when external storage is unavailable or not writable.
     */
    fun sdCardRoot(context: Context): File? {
        val filesDir = context.getExternalFilesDir(null) ?: run {
            Log.e(TAG, "getExternalFilesDir(null) returned null")
            return null
        }
        if (!filesDir.exists() && !filesDir.mkdirs()) {
            Log.e(TAG, "Cannot create app files dir: ${filesDir.absolutePath}")
            return null
        }

        val packageRoot = filesDir.parentFile ?: run {
            Log.e(TAG, "Cannot resolve parent of ${filesDir.absolutePath}")
            return null
        }

        val root = File(packageRoot, FOLDER_NAME)
        if (!root.exists() && !root.mkdirs()) {
            Log.e(
                TAG,
                "Cannot create EdgeTX root: ${root.absolutePath} " +
                    "(parent writable=${packageRoot.canWrite()})"
            )
            return null
        }
        if (!root.isDirectory || !root.canWrite()) {
            Log.e(TAG, "EdgeTX root not writable: ${root.absolutePath}")
            return null
        }
        return root
    }

    /** @return true when bundled SD content is present (or already seeded). */
    fun ensureSeeded(context: Context): Boolean {
        val root = sdCardRoot(context) ?: return false
        SdCardSeeder.ensureSeeded(context, root)
        return File(root, "edgetx.sdcard.version").exists()
    }

    fun resolveRoot(context: Context): File {
        val root = sdCardRoot(context)
            ?: throw IllegalStateException("EdgeTX storage unavailable")
        if (!File(root, "edgetx.sdcard.version").exists()) {
            Log.w(TAG, "SD card not seeded yet; extracting now")
            SdCardSeeder.ensureSeeded(context, root)
        }
        Log.i(TAG, "Using ${root.absolutePath}")
        return root
    }

    fun hasRadioSettings(root: File): Boolean {
        return File(root, "RADIO/radio.yml").exists()
    }
}
