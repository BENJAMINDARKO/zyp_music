package com.benjamindarko.monochrome

import android.app.ActivityManager
import android.content.Context
import androidx.annotation.NonNull
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.ryanheise.audioservice.AudioServiceFragmentActivity

class MainActivity : AudioServiceFragmentActivity() {
    private val CHANNEL = "com.benjamindarko.monochrome/system"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "clearAppData") {
                try {
                    val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                    val success = activityManager.clearApplicationUserData()
                    result.success(success)
                } catch (e: Exception) {
                    result.error("FAILED", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
