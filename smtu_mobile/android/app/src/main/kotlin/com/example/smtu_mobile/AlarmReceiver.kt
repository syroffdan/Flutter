package com.example.smtu_mobile

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/// Получает срабатывание будильника и запускает экран сигнала.
///
/// Прямой запуск Activity из фона ограничен, поэтому основной путь —
/// уведомление с full-screen intent: на заблокированном экране система
/// сама покажет [AlarmActivity].
class AlarmReceiver : BroadcastReceiver() {
    companion object {
        private const val CHANNEL_ID = "alarm_firing"
        const val NOTIFICATION_ID = 6000

        fun alarmIntent(context: Context, id: Int, message: String): Intent {
            return Intent(context, AlarmActivity::class.java).apply {
                putExtra(AlarmScheduler.EXTRA_ID, id)
                putExtra(AlarmScheduler.EXTRA_MESSAGE, message)
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS,
                )
            }
        }

        fun ensureChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

            val manager =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            if (manager.getNotificationChannel(CHANNEL_ID) != null) return

            val channel = NotificationChannel(
                CHANNEL_ID,
                "Сигнал будильника",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Экран будильника поверх блокировки"
                setShowBadge(false)
                // Звук и вибрацию даёт сам экран будильника.
                setSound(null, null)
                enableVibration(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }

            manager.createNotificationChannel(channel)
        }

        fun show(context: Context, id: Int, message: String) {
            ensureChannel(context)

            val manager =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            val fullScreen = PendingIntent.getActivity(
                context,
                id,
                alarmIntent(context, id, message),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context)
            }

            builder
                .setSmallIcon(R.mipmap.launcher_icon)
                .setContentTitle("Будильник")
                .setContentText(message)
                .setContentIntent(fullScreen)
                .setFullScreenIntent(fullScreen, true)
                .setOngoing(true)
                .setAutoCancel(false)
                .setOnlyAlertOnce(true)
                .setCategory(Notification.CATEGORY_ALARM)
                .setVisibility(Notification.VISIBILITY_PUBLIC)

            manager.notify(NOTIFICATION_ID, builder.build())
        }

        fun cancel(context: Context) {
            val manager =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.cancel(NOTIFICATION_ID)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra(AlarmScheduler.EXTRA_ID, 0)
        val message = intent.getStringExtra(AlarmScheduler.EXTRA_MESSAGE) ?: "Пора на пару"

        try {
            show(context, id, message)
        } catch (_: Exception) {
            // Уведомление не критично: ниже пробуем открыть экран напрямую.
        }

        // На старых версиях и когда запуск из фона разрешён экран
        // открывается сразу, без ожидания полного уведомления.
        try {
            context.startActivity(alarmIntent(context, id, message))
        } catch (_: Exception) {
            // На современных Android это запрещено — экран покажет
            // full-screen intent.
        }
    }
}
