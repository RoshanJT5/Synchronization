package com.synchronization.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat

/**
 * SyncForegroundService
 *
 * A real Android Foreground Service that tells the OS:
 *   "This app is actively playing media — do NOT kill it."
 *
 * This is exactly what Spotify, YouTube Music, AmpMe, and every music app
 * uses to survive when the screen is off. Without this, Android Doze mode
 * kills network connections and CPU after ~5-10 minutes.
 *
 * The service:
 *  1. Shows a persistent notification ("Audio session is active")
 *  2. Acquires a PARTIAL_WAKE_LOCK (CPU stays on, screen stays off)
 *  3. Declares foregroundServiceType="mediaPlayback" (Android 10+)
 *  4. Returns START_STICKY so it restarts if the system kills it
 */
class SyncForegroundService : Service() {

    companion object {
        const val CHANNEL_ID = "sync_foreground_channel"
        const val NOTIFICATION_ID = 1001
    }

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = createNotification()

        // On Android 10+ we must specify the foreground service type.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        acquireWakeLock()
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        releaseWakeLock()
        super.onDestroy()
    }

    // -- Notification channel (required Android 8+) --

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Synchronization Service",
                NotificationManager.IMPORTANCE_LOW   // no sound, low priority
            ).apply {
                description = "Keeps audio synchronization active in the background"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    // -- Build the persistent notification --

    private fun createNotification(): Notification {
        // Tapping the notification opens the app.
        val openIntent: Intent = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }

        val pendingOpenIntent = PendingIntent.getActivity(
            this, 0, openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Synchronization")
            .setContentText("Audio session is active")
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setOngoing(true)
            .setContentIntent(pendingOpenIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }

    // -- Partial wake lock (CPU stays on, screen stays off) --

    private fun acquireWakeLock() {
        if (wakeLock != null) return  // already held
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "Synchronization::AudioSession"
        ).apply {
            acquire()  // released in onDestroy()
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
    }
}
