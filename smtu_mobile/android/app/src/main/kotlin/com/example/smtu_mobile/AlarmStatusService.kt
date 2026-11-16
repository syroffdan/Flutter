package com.example.smtu_mobile

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder

/// Держит в шторке постоянное уведомление о ближайшем будильнике.
///
/// Обычное уведомление снимается вместе с приложением, когда его убирают
/// свайпом из недавних. Уведомление foreground-сервиса остаётся, поэтому
/// сервис не останавливается при удалении задачи.
class AlarmStatusService : Service() {
    companion object {
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"
        const val EXTRA_WHEN = "when"
        const val EXTRA_OPEN_ALARMS = "open_alarms"

        private const val CHANNEL_ID = "alarm_status"
        private const val NOTIFICATION_ID = 5000
        private const val PREFS_NAME = "alarm_status_service"
        private const val PREF_TITLE = "title"
        private const val PREF_BODY = "body"
        private const val PREF_WHEN = "when"

        fun start(context: Context, title: String, body: String, whenMillis: Long) {
            val intent = Intent(context, AlarmStatusService::class.java).apply {
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_BODY, body)
                putExtra(EXTRA_WHEN, whenMillis)
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, AlarmStatusService::class.java))
        }
    }

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

        // После перезапуска сервиса система приходит без intent — берём
        // последнее показанное уведомление, чтобы не потерять данные.
        val title = intent?.getStringExtra(EXTRA_TITLE)
            ?: prefs.getString(PREF_TITLE, null)
            ?: "Будильник"
        val body = intent?.getStringExtra(EXTRA_BODY)
            ?: prefs.getString(PREF_BODY, null)
            ?: ""
        val whenMillis = if (intent != null && intent.hasExtra(EXTRA_WHEN)) {
            intent.getLongExtra(EXTRA_WHEN, 0L)
        } else {
            prefs.getLong(PREF_WHEN, 0L)
        }

        prefs.edit()
            .putString(PREF_TITLE, title)
            .putString(PREF_BODY, body)
            .putLong(PREF_WHEN, whenMillis)
            .apply()

        startForeground(NOTIFICATION_ID, buildNotification(title, body, whenMillis))

        return START_STICKY
    }

    /// Приложение убрали из недавних: сервис и уведомление должны остаться.
    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (manager.getNotificationChannel(CHANNEL_ID) != null) return

        val channel = NotificationChannel(
            CHANNEL_ID,
            "Ближайший будильник",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "Постоянное уведомление о ближайшем автоматическом будильнике"
            setShowBadge(false)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }

        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(
        title: String,
        body: String,
        whenMillis: Long,
    ): Notification {
        val openIntent = Intent(this, MainActivity::class.java).apply {
            putExtra(EXTRA_OPEN_ALARMS, true)
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP,
            )
        }

        val contentIntent = PendingIntent.getActivity(
            this,
            NOTIFICATION_ID,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        builder
            .setSmallIcon(R.mipmap.launcher_icon)
            .setContentTitle(title)
            .setContentText(body)
            .setContentIntent(contentIntent)
            .setOngoing(true)
            .setAutoCancel(false)
            .setOnlyAlertOnce(true)
            .setShowWhen(true)
            .setCategory(Notification.CATEGORY_ALARM)
            .setVisibility(Notification.VISIBILITY_PUBLIC)

        if (whenMillis > 0L) {
            builder.setWhen(whenMillis)
        }

        return builder.build()
    }
}
