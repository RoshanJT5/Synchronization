package com.synchronization.app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.synchronization.app/foreground_service"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startForegroundService" -> {
                        startSyncService()
                        result.success(true)
                    }
                    "stopForegroundService" -> {
                        stopSyncService()
                        result.success(true)
                    }
                    "isBatteryOptimizationDisabled" -> {
                        result.success(isBatteryOptimizationDisabled())
                    }
                    "requestDisableBatteryOptimization" -> {
                        requestDisableBatteryOptimization()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // Start the foreground service.  Uses startForegroundService() on
    // Android 8+ so the system knows to expect a startForeground() call
    // within 5 seconds (our service calls it immediately).
    private fun startSyncService() {
        val intent = Intent(this, SyncForegroundService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    // Stop the foreground service.  This triggers onDestroy() on the
    // service which releases the partial wake lock.
    private fun stopSyncService() {
        val intent = Intent(this, SyncForegroundService::class.java)
        stopService(intent)
    }

    // Check whether this app is already exempt from battery optimization.
    // Returns true if exempt (good) or if the API is unavailable (<M).
    private fun isBatteryOptimizationDisabled(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            return pm.isIgnoringBatteryOptimizations(packageName)
        }
        return true  // Not applicable before Android M
    }

    // Show the system dialog asking the user to exempt this app from
    // battery optimization.  This is a system-level popup — the user
    // taps "Allow" or "Deny" and stays in the app.
    private fun requestDisableBatteryOptimization() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val intent = Intent(
                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
                ).apply {
                    data = Uri.parse("package:$packageName")
                }
                startActivity(intent)
            } catch (e: Exception) {
                // Some OEMs strip this intent.  Fall back to the full
                // battery optimization list so the user can find the app.
                try {
                    val fallback = Intent(
                        Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS
                    )
                    startActivity(fallback)
                } catch (_: Exception) {
                    // Nothing we can do — the OEM removed both intents.
                }
            }
        }
    }
}
