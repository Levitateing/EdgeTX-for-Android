import java.io.File
import java.security.MessageDigest

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

val sdCardSource = rootProject.file("SD-Card-Files")
val sdCardAssetsRoot = layout.buildDirectory.dir("generated/sdcardAssets")
val sdCardAssetsDir = sdCardAssetsRoot.map { it.dir("sdcard") }

fun computeSdCardFingerprint(source: File): String {
    if (!source.isDirectory) return "empty"
    val digest = MessageDigest.getInstance("SHA-256")
    source.walkTopDown()
        .filter { it.isFile }
        .sortedBy { it.relativeTo(source).invariantSeparatorsPath }
        .forEach { file ->
            val rel = file.relativeTo(source).invariantSeparatorsPath
            digest.update(rel.toByteArray(Charsets.UTF_8))
            digest.update(0)
            file.inputStream().use { input ->
                val buffer = ByteArray(8192)
                while (true) {
                    val read = input.read(buffer)
                    if (read <= 0) break
                    digest.update(buffer, 0, read)
                }
            }
        }
    return digest.digest().joinToString("") { "%02x".format(it) }.take(16)
}

android {
    namespace = "io.github.levitateing.etxandroid"
    compileSdk = 35
    ndkVersion = "27.0.12077973"

    defaultConfig {
        applicationId = "io.github.levitateing.etxandroid"
        minSdk = 26
        targetSdk = 35
        versionCode = 57
        versionName = "0.53.1-unofficial"

        externalNativeBuild {
            cmake {
                cppFlags += listOf("-std=c++17", "-O2", "-fno-exceptions")
                arguments += listOf(
                    "-DANDROID_STL=c++_shared"
                )
                // Phones only. EdgeTX desktop SIMU is unrelated to Android ABI choice.
                abiFilters += listOf("arm64-v8a")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }

    sourceSets {
        getByName("main") {
            assets.srcDir(sdCardAssetsRoot)
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.appcompat:appcompat:1.7.0")
    // USB CDC host (phone OTG → radio)
    implementation("com.github.mik3y:usb-serial-for-android:3.8.0")
}

// Sync (not Copy): mirror SD-Card-Files and delete stale generated assets.
val packSdCardAssets by tasks.registering(Sync::class) {
    from(sdCardSource)
    into(sdCardAssetsDir)
    doLast {
        val fingerprint = computeSdCardFingerprint(sdCardSource)
        sdCardAssetsDir.get().file("bundle.version").asFile.writeText(fingerprint)
        logger.lifecycle("SD card bundle synced from ${sdCardSource.path} (fingerprint=$fingerprint)")
    }
}

tasks.named("preBuild") {
    dependsOn(packSdCardAssets)
}
