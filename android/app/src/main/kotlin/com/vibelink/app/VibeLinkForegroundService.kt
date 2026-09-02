package com.vibelink.app

import android.app.*
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.app.AlarmManager
import android.os.PowerManager
import android.os.SystemClock
import androidx.core.app.NotificationCompat

class VibeLinkForegroundService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null

    private var _stoppedByUser = false

    companion object {
        const val CHANNEL_ID = "vibelink_background_channel"
        const val NOTIFICATION_ID = 1001
        const val ACTION_START = "ACTION_START"
        const val ACTION_STOP = "ACTION_STOP"
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        acquireWakeLock()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            _stoppedByUser = true
            stopForeground(true)
            stopSelf()
            return START_NOT_STICKY
        }

        val notification = createNotification()
        startForeground(NOTIFICATION_ID, notification)
        acquireWakeLock()

        return START_STICKY
    }

    private fun acquireWakeLock() {
        if (wakeLock == null) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "VibeLink::BackgroundServiceWakeLock"
            )
            wakeLock?.setReferenceCounted(false)
        }
        if (wakeLock?.isHeld == false) {
            wakeLock?.acquire()
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "VibeLink Doimiy Ulanish Xizmati",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Telefon ekrani o'chganda ham vibratsiyalarni real-vaqtda qabul qilish uchun"
                setShowBadge(false)
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            manager?.createNotificationChannel(channel)
        }
    }

    private fun createNotification(): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("VibeLink — Onlayn")
            .setContentText("Ekran o'chiq holatda ham signallarni qabul qilishga tayyor")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        // App was swiped from Recents — schedule a restart in 1 second
        val restartIntent = Intent(applicationContext, VibeLinkForegroundService::class.java).apply {
            setPackage(packageName)
        }
        val pendingIntent = PendingIntent.getService(
            this, 1, restartIntent,
            PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE
        )
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmManager.set(
            AlarmManager.ELAPSED_REALTIME,
            SystemClock.elapsedRealtime() + 1000,
            pendingIntent
        )
    }

    override fun onDestroy() {
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        // Restart service if killed by system (not by user-initiated ACTION_STOP)
        if (!_stoppedByUser) {
            val restartIntent = Intent(applicationContext, VibeLinkForegroundService::class.java)
            startService(restartIntent)
        }
        _stoppedByUser = false
        super.onDestroy()
    }
}
