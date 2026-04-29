package com.syncronizationapp

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder

class PlaybackService : Service() {
  override fun onBind(intent: Intent?): IBinder? = null

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    startForeground(NOTIFICATION_ID, buildNotification())
    return START_STICKY
  }

  override fun onDestroy() {
    stopForeground(STOP_FOREGROUND_REMOVE)
    super.onDestroy()
  }

  private fun buildNotification(): Notification {
    val channelId = "syncronization_playback"

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      val channel = NotificationChannel(
          channelId,
          "Syncronization Playback",
          NotificationManager.IMPORTANCE_LOW
      )
      channel.description = "Keeps remote speaker playback active while the screen is off."
      getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      Notification.Builder(this, channelId)
    } else {
      Notification.Builder(this)
    }

    return builder
        .setContentTitle("Syncronization is playing")
        .setContentText("Receiving audio from your browser.")
        .setSmallIcon(android.R.drawable.ic_media_play)
        .setOngoing(true)
        .build()
  }

  companion object {
    private const val NOTIFICATION_ID = 4101
  }
}
