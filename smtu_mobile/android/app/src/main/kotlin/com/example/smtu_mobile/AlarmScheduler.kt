package com.example.smtu_mobile

import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject

/// Единая точка установки будильников приложения: используется из Flutter
/// (MainActivity) и после перезагрузки телефона (BootReceiver).
object AlarmScheduler {
    const val ACTION_RING = "com.example.smtu_mobile.ALARM_RING"
    const val EXTRA_ID = "alarm_id"
    const val EXTRA_MESSAGE = "message"

    private const val PREFS = "scheduled_alarms"
    private const val KEY = "alarms"
    private const val MAX_ALARMS = 16

    data class Alarm(
        val id: Int,
        val triggerAtMillis: Long,
        val message: String,
    )

    /// Android 12+ может запрещать точные будильники: без этого разрешения
    /// `setAlarmClock` бросает SecurityException.
    fun canScheduleExact(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true

        val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        return manager.canScheduleExactAlarms()
    }

    /// Android 14+ может отключать полноэкранные уведомления: без этого
    /// разрешения экран будильника поверх блокировки не покажется.
    fun canUseFullScreenIntent(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return true

        val manager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        return manager.canUseFullScreenIntent()
    }

    /// Ставит будильники и сохраняет план, чтобы восстановить его после
    /// перезагрузки. Возвращает true, если удалось поставить все будильники.
    ///
    /// Без разрешения на точные будильники ничего не ставим: неточный
    /// сигнал для пары бесполезен, а проблему лучше показать пользователю.
    fun schedule(context: Context, alarms: List<Alarm>): Boolean {
        if (!canScheduleExact(context)) return false

        cancelAll(context)

        val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val placed = mutableListOf<Alarm>()

        for (alarm in alarms) {
            val pending = pendingIntent(context, alarm.id, alarm.message)

            try {
                manager.setAlarmClock(
                    AlarmManager.AlarmClockInfo(alarm.triggerAtMillis, pending),
                    pending,
                )
                placed.add(alarm)
            } catch (_: Exception) {
                // Разрешение могли отозвать между проверкой и установкой.
            }
        }

        save(context, placed)

        return placed.size == alarms.size
    }

    fun cancelAll(context: Context) {
        val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

        for (id in 0 until MAX_ALARMS) {
            val pending = PendingIntent.getBroadcast(
                context,
                id,
                ringIntent(context, id, ""),
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
            )

            if (pending != null) {
                manager.cancel(pending)
                pending.cancel()
            }
        }
    }

    /// Переустанавливает будильники из сохранённого плана. AlarmManager
    /// очищается при выключении телефона, поэтому это нужно после загрузки.
    ///
    /// Верхняя и нижняя недели чередуются, поэтому прошедшие даты нельзя
    /// переносить на неделю вперёд: восстанавливаем только те будильники,
    /// которые ещё не сработали.
    fun rescheduleFromStorage(context: Context) {
        val stored = load(context)

        if (stored.isEmpty()) return

        val now = System.currentTimeMillis()
        val future = stored
            .filter { it.triggerAtMillis > now }
            .sortedBy { it.triggerAtMillis }

        if (future.isEmpty()) {
            // Всё, что было запланировано, уже прошло: чистим план, новый
            // построит приложение при следующей загрузке расписания.
            save(context, emptyList())
            return
        }

        // Без разрешения на точные будильники план сохраняем: его можно
        // восстановить, когда пользователь выдаст разрешение.
        if (!canScheduleExact(context)) return

        schedule(context, future)
    }

    fun save(context: Context, alarms: List<Alarm>) {
        val array = JSONArray()

        for (alarm in alarms) {
            array.put(
                JSONObject().apply {
                    put("id", alarm.id)
                    put("triggerAtMillis", alarm.triggerAtMillis)
                    put("message", alarm.message)
                },
            )
        }

        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY, array.toString())
            .apply()
    }

    fun load(context: Context): List<Alarm> {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY, null) ?: return emptyList()

        return try {
            val array = JSONArray(raw)
            val alarms = mutableListOf<Alarm>()

            for (index in 0 until array.length()) {
                val item = array.getJSONObject(index)

                alarms.add(
                    Alarm(
                        id = item.getInt("id"),
                        triggerAtMillis = item.getLong("triggerAtMillis"),
                        message = item.optString("message", "Пора на пару"),
                    ),
                )
            }

            alarms
        } catch (_: Exception) {
            emptyList()
        }
    }

    fun pendingIntent(context: Context, id: Int, message: String): PendingIntent {
        return PendingIntent.getBroadcast(
            context,
            id,
            ringIntent(context, id, message),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun ringIntent(context: Context, id: Int, message: String): Intent {
        // data делает PendingIntent уникальным для каждого будильника.
        return Intent(context, AlarmReceiver::class.java).apply {
            action = ACTION_RING
            data = Uri.parse("smtu://alarm/$id")
            putExtra(EXTRA_ID, id)
            putExtra(EXTRA_MESSAGE, message)
        }
    }
}
