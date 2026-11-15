package com.example.smtu_mobile

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.provider.AlarmClock
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "smtu/system_alarm",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setAlarm" -> {
                    val hour = call.argument<Int>("hour")
                    val minute = call.argument<Int>("minute")
                    val message = call.argument<String>("message") ?: "Первая пара"
                    val skipUi = call.argument<Boolean>("skipUi") ?: true
                    val weekdays = call.argument<List<Int>>("weekdays") ?: emptyList()

                    if (hour == null || minute == null) {
                        result.error("bad_args", "hour and minute are required", null)
                    } else {
                        result.success(setAlarm(hour, minute, message, skipUi, weekdays))
                    }
                }
                "scheduleAlarms" -> {
                    val alarms = call.argument<List<Map<String, Any?>>>("alarms")
                        ?: emptyList()

                    try {
                        scheduleAlarms(alarms)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error(
                            "schedule_failed",
                            "${e.javaClass.simpleName}: ${e.message}",
                            null,
                        )
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun scheduleAlarms(alarms: List<Map<String, Any?>>) {
        val manager = getSystemService(Context.ALARM_SERVICE) as AlarmManager

        // Снимаем предыдущие будильники приложения.
        for (id in 0..15) {
            val pending = PendingIntent.getActivity(
                this,
                id,
                Intent(this, AlarmActivity::class.java),
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
            )

            if (pending != null) {
                manager.cancel(pending)
                pending.cancel()
            }
        }

        for ((index, alarm) in alarms.withIndex()) {
            val triggerAt = (alarm["triggerAtMillis"] as? Number)?.toLong()
                ?: continue
            val message = alarm["message"] as? String ?: "Пора на пару"
            val id = (alarm["id"] as? Number)?.toInt() ?: index

            val pending = PendingIntent.getActivity(
                this,
                id,
                alarmIntent(message),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

            try {
                manager.setAlarmClock(
                    AlarmManager.AlarmClockInfo(triggerAt, pending),
                    pending,
                )
            } catch (e: SecurityException) {
                // Если точные будильники запрещены, ставим неточный —
                // он может сработать с небольшой задержкой.
                manager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    triggerAt,
                    pending,
                )
            }
        }
    }

    private fun alarmIntent(message: String): Intent {
        return Intent(this, AlarmActivity::class.java).apply {
            putExtra("message", message)
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS,
            )
        }
    }

    private fun setAlarm(
        hour: Int,
        minute: Int,
        message: String,
        skipUi: Boolean,
        weekdays: List<Int>,
    ): Boolean {
        return try {
            val intent = Intent(AlarmClock.ACTION_SET_ALARM).apply {
                putExtra(AlarmClock.EXTRA_HOUR, hour)
                putExtra(AlarmClock.EXTRA_MINUTES, minute)
                putExtra(AlarmClock.EXTRA_MESSAGE, message)
                putExtra(AlarmClock.EXTRA_SKIP_UI, skipUi)
                if (weekdays.isNotEmpty()) {
                    putExtra(AlarmClock.EXTRA_DAYS, ArrayList(weekdays))
                }
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }

            startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }
}
