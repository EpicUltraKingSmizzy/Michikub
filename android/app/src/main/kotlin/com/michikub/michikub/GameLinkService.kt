package com.michikub.michikub

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Keeps an online game's connection alive while Michikub is in the background (hosting a room,
 * or playing as a guest): a foreground service with an ongoing notification stops Android from
 * freezing or killing the app, so the WebRTC link to the other phones stays up. It does no
 * work itself; the game keeps running in the Flutter engine.
 */
class GameLinkService : Service() {
    companion object {
        const val CHANNEL = "game_link"
        const val NOTIFICATION_ID = 7
        const val EXTRA_TEXT = "text"
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val text = intent?.getStringExtra(EXTRA_TEXT) ?: "Keeping your game connected"
        val nm = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL, "Online game", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "Shown while an online game stays connected in the background"
                    setShowBadge(false)
                }
            )
        }
        val open = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(this, CHANNEL) else Notification.Builder(this)
        val n = builder
            .setContentTitle("Michikub")
            .setContentText(text)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setContentIntent(open)
            .build()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIFICATION_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
            } else {
                startForeground(NOTIFICATION_ID, n)
            }
        } catch (e: Exception) {
            // Not allowed right now (e.g. started from the background): the game falls back to
            // pausing while the host is away.
            stopSelf()
        }
        return START_NOT_STICKY
    }

    // Android 15+: data-sync services get about 6 hours a day; then the system asks us to stop.
    override fun onTimeout(startId: Int, fgsType: Int) {
        stopSelf()
    }

    // The app was swiped away: no game to keep alive.
    override fun onTaskRemoved(rootIntent: Intent?) {
        stopSelf()
    }
}
