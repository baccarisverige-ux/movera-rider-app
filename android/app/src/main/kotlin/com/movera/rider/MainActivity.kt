package com.movera.rider

import android.util.Log
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.IntegrityServiceException
import com.google.android.play.core.integrity.IntegrityTokenRequest
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // Contract v0.18.138 (deviceCheck.check, Android): a Play Integrity token
    // (classic request) with the app's binding as the nonce. Any failure
    // answers null: the sign-in request goes without a check.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "movera/device_check",
        ).setMethodCallHandler { call, result ->
            val nonce = call.argument<String>("nonce")
            if (call.method != "playIntegrity" || nonce.isNullOrEmpty()) {
                result.notImplemented()
                return@setMethodCallHandler
            }
            try {
                IntegrityManagerFactory.create(applicationContext)
                    .requestIntegrityToken(IntegrityTokenRequest.builder().setNonce(nonce).build())
                    .addOnSuccessListener { answer -> result.success(answer.token()) }
                    .addOnFailureListener { error ->
                        // Debug level, the failure code only (never a token or number).
                        val code = (error as? IntegrityServiceException)?.errorCode?.toString()
                            ?: error.javaClass.simpleName
                        Log.d("MoveraDeviceCheck", "Play Integrity failed: " + code)
                        result.success(null)
                    }
            } catch (_: Exception) {
                result.success(null)
            }
        }
    }
}
