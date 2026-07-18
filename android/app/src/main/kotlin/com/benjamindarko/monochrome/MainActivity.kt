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

        com.ryanheise.just_audio.AdvancedVocalRemoverProcessor.onMonoTrackEncountered = {
            runOnUiThread {
                val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.benjamindarko.monochrome/vocal_control")
                ch.invokeMethod("onMonoTrack", null)
            }
        }

        val vocalChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.benjamindarko.monochrome/vocal_control")
        vocalChannel.setMethodCallHandler { call, result ->
            if (call.method == "setVocalReduction") {
                val factor = call.argument<Double>("factor")?.toFloat() ?: 0.0f
                com.ryanheise.just_audio.AdvancedVocalRemoverProcessor.broadcastVocalReduction(factor)
                result.success(null)
            } else {
                result.notImplemented()
            }
        }

        val eqChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.benjamindarko.monochrome/equalizer_control")
        eqChannel.setMethodCallHandler { call, result ->
            if (call.method == "setEqualizerConfig") {
                val enabled = call.argument<Boolean>("enabled") ?: true
                val preamp = call.argument<Double>("preamp")?.toFloat() ?: 0.0f
                val bassBoost = call.argument<Double>("bassBoost")?.toFloat() ?: 24.0f
                val virtualizer = call.argument<Double>("virtualizer")?.toFloat() ?: 18.0f
                val limiterEnabled = call.argument<Boolean>("limiterEnabled") ?: true

                val rawGains = call.argument<List<Double>>("bandGains")
                val gains = FloatArray(16)
                if (rawGains != null) {
                    for (i in 0 until 16.coerceAtMost(rawGains.size)) {
                        gains[i] = rawGains[i].toFloat()
                    }
                }

                com.ryanheise.just_audio.AdvancedEqualizerProcessor.broadcastConfig(
                    enabled = enabled,
                    gains = gains,
                    preamp = preamp,
                    bass = bassBoost,
                    virtualizer = virtualizer,
                    limiter = limiterEnabled
                )
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }
}
