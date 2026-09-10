package io.github.levitateing.etxandroid

import android.content.Context
import android.content.res.AssetManager
import android.util.Log
import java.io.File
import java.io.IOException

/**
 * Extracts bundled SD card content from APK assets into the app-private EdgeTX root.
 */
object SdCardSeeder {
    private const val TAG = "EdgeTXSdSeed"
    private const val ASSET_ROOT = "sdcard"
    /** APK asset only — never copied into the EdgeTX SD tree. */
    private const val BUNDLE_VERSION = "bundle.version"

    fun ensureSeeded(context: Context, root: File) {
        removeLegacyBundleMarker(root)

        val bundledVersion = readAssetText(context.assets, "$ASSET_ROOT/$BUNDLE_VERSION")
        if (bundledVersion.isNullOrBlank()) {
            Log.e(TAG, "Missing bundled $BUNDLE_VERSION in APK assets")
            return
        }

        val localVersionFile = localVersionFile(context)
        val localVersion = if (localVersionFile.exists()) {
            localVersionFile.readText().trim()
        } else {
            ""
        }

        if (localVersion == bundledVersion && File(root, "edgetx.sdcard.version").exists()) {
            Log.i(TAG, "SD bundle up to date ($bundledVersion)")
            return
        }

        Log.i(TAG, "Extracting SD bundle $bundledVersion -> ${root.absolutePath}")
        try {
            val bundledFiles = listBundledFiles(context.assets)
            extractAssetPath(context.assets, ASSET_ROOT, root)
            removeOrphanFiles(root, bundledFiles)
            localVersionFile.writeText(bundledVersion)
            removeLegacyBundleMarker(root)
        } catch (e: IOException) {
            Log.e(TAG, "SD bundle extraction failed", e)
        }
    }

    private fun localVersionFile(context: Context): File {
        return File(context.filesDir, BUNDLE_VERSION)
    }

    /** Remove bundle.version left in SD root by older builds. */
    private fun removeLegacyBundleMarker(root: File) {
        val legacy = File(root, BUNDLE_VERSION)
        if (legacy.exists() && !legacy.delete()) {
            Log.w(TAG, "Could not delete legacy ${legacy.absolutePath}")
        }
    }

    private fun readAssetText(assets: AssetManager, path: String): String? {
        return try {
            assets.open(path).bufferedReader().use { it.readText().trim() }
        } catch (_: IOException) {
            null
        }
    }

    private fun listBundledFiles(assets: AssetManager): Set<String> {
        val files = mutableSetOf<String>()
        walkAssetTree(assets, ASSET_ROOT, "") { relPath ->
            if (relPath.isNotEmpty()) {
                files.add(relPath)
            }
        }
        return files
    }

    private fun walkAssetTree(
        assets: AssetManager,
        assetPath: String,
        relPath: String,
        onFile: (String) -> Unit
    ) {
        val children = assets.list(assetPath)
        when {
            children == null -> return
            children.isEmpty() -> onFile(relPath)
            else -> {
                for (name in children) {
                    if (assetPath == ASSET_ROOT && name == BUNDLE_VERSION) {
                        continue
                    }
                    val childAssetPath = "$assetPath/$name"
                    val childRelPath = if (relPath.isEmpty()) name else "$relPath/$name"
                    walkAssetTree(assets, childAssetPath, childRelPath, onFile)
                }
            }
        }
    }

    private fun removeOrphanFiles(root: File, bundledFiles: Set<String>) {
        if (!root.isDirectory) return
        root.walkTopDown()
            .filter { it.isFile }
            .forEach { file ->
                val rel = file.relativeTo(root).invariantSeparatorsPath
                if (rel !in bundledFiles) {
                    if (file.delete()) {
                        Log.i(TAG, "Removed stale SD file: $rel")
                    } else {
                        Log.w(TAG, "Could not remove stale SD file: $rel")
                    }
                }
            }
    }

    @Throws(IOException::class)
    private fun extractAssetPath(assets: AssetManager, assetPath: String, dest: File) {
        val children = assets.list(assetPath)
        when {
            children == null -> return
            children.isEmpty() -> copyAssetFile(assets, assetPath, dest)
            else -> {
                if (!dest.exists() && !dest.mkdirs()) {
                    throw IOException("Cannot create directory: ${dest.absolutePath}")
                }
                for (name in children) {
                    if (assetPath == ASSET_ROOT && name == BUNDLE_VERSION) {
                        continue
                    }
                    extractAssetPath(assets, "$assetPath/$name", File(dest, name))
                }
            }
        }
    }

    @Throws(IOException::class)
    private fun copyAssetFile(assets: AssetManager, assetPath: String, dest: File) {
        if (dest.name == BUNDLE_VERSION) {
            return
        }
        dest.parentFile?.mkdirs()
        assets.open(assetPath).use { input ->
            dest.outputStream().use { output ->
                input.copyTo(output)
            }
        }
    }
}
