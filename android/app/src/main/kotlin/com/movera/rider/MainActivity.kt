package com.movera.rider

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterFragmentActivity
import java.io.File
import org.json.JSONObject

// v0.18.136 stripeFees: flutter_stripe PaymentSheet needs a FragmentActivity and an AppCompat theme.
class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // v0.18.157 (owner 2026-11-24 "Add to admin all kind of crash"): before the Flutter engine starts.
        MoveraCrashCatcher.install(applicationContext)
        super.onCreate(savedInstanceState)
    }
}

/**
 * v0.18.157 crash catcher (contract.json#crashCatcher.nativeReason), no third-party SDK: an uncaught Java/Kotlin
 * exception writes its class, message and stack to files/movera_native_crash.json (then the previous handler runs, so
 * Android closes the app as before); on Android 11+ the last ApplicationExitInfo names a native crash, an ANR or a
 * crash when no file was written (each exit once). movera_device.json carries the model and the Android version. The
 * Dart side reads and deletes the crash file at the next launch. Keep the names in step with crash_files.dart.
 */
object MoveraCrashCatcher {
    @Volatile private var installed = false

    fun install(context: Context) {
        if (installed) return
        installed = true
        try {
            val dir = context.filesDir
            val crashFile = File(dir, "movera_native_crash.json")
            File(dir, "movera_device.json").writeText(
                JSONObject()
                    .put("model", "${Build.MANUFACTURER} ${Build.MODEL}".take(80))
                    .put("os", "Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})")
                    .toString(),
            )
            val previous = Thread.getDefaultUncaughtExceptionHandler()
            Thread.setDefaultUncaughtExceptionHandler { thread, error ->
                try {
                    if (!crashFile.exists()) {
                        crashFile.writeText(
                            JSONObject()
                                .put("name", error.javaClass.name)
                                .put("reason", (error.message ?: "").take(1000))
                                .put("stack", Log.getStackTraceString(error).take(12000))
                                .put("thread", thread.name)
                                .toString(),
                        )
                    }
                } catch (_: Throwable) {
                }
                previous?.uncaughtException(thread, error)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) lastExit(context, crashFile)
        } catch (_: Throwable) {
            // The catcher must never stop the app from starting.
        }
    }

    private fun lastExit(context: Context, crashFile: File) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        try {
            val manager = context.getSystemService(ActivityManager::class.java) ?: return
            val last = manager.getHistoricalProcessExitReasons(context.packageName, 0, 1).firstOrNull() ?: return
            val prefs = context.getSharedPreferences("movera_crash_catcher", Context.MODE_PRIVATE)
            if (prefs.getLong("lastExitAt", 0L) == last.timestamp) return
            prefs.edit().putLong("lastExitAt", last.timestamp).apply()
            val name = when (last.reason) {
                ApplicationExitInfo.REASON_CRASH_NATIVE -> "REASON_CRASH_NATIVE"
                ApplicationExitInfo.REASON_ANR -> "REASON_ANR"
                ApplicationExitInfo.REASON_CRASH -> "REASON_CRASH"
                else -> return
            }
            if (crashFile.exists()) return
            crashFile.writeText(
                JSONObject()
                    .put("name", name)
                    .put("reason", (last.description ?: "").take(1000))
                    .put("stack", "")
                    .toString(),
            )
        } catch (_: Throwable) {
        }
    }
}
