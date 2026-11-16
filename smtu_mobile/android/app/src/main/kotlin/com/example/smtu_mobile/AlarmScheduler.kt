package com.example.smtu_mobile

import android.app.AlarmManager
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
    private const val WEEK_MILLIS = 7L * 24 * 60 * 60 * 1000
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

    /// Ставит будильники и сохраняет план, чтобы восстановить его после
    /// перезагрузки. Возвращает true, если удалось поставить все будильники.
    fun schedule(context: Context, alarms: List<Alarm>): Boolean {
        cancelAll(context)

        val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val exact = canScheduleExact(context)
        var scheduled = 0

        for (alarm in alarms) {
            val pending = pendingIntent(context, alarm.id, alarm.message)
            val ok = try {
                if (exact) {
                    manager.setAlarmClock(
                        AlarmManager.AlarmClockInfo(alarm.triggerAtMillis, pending),
                        pending,
                    )
                } else {
                    // Без разрешения на точные будильники система может
                    // сдвинуть сигнал, но он не потеряется.
                    manager.setAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        alarm.triggerAtMillis,
                        pending,
                    )
                }
                true
            } catch (_: Exception) {
                false
            }

            if (ok) scheduled++
        }

        save(context, alarms)

        return scheduled == alarms.size
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
    fun rescheduleFromStorage(context: Context) {
        val stored = load(context)

        if (stored.isEmpty()) return

        val now = System.currentTimeMillis()

        // План недельный: прошедшие времена переносим на следующую неделю.
        val shifted = stored.map { alarm ->
            var trigger = alarm.triggerAtMillis

            while (trigger <= now) {
                trigger += WEEK_MILLIS
            }

            alarm.copy(triggerAtMillis = trigger)
        }

        schedule(context, shifted)
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
