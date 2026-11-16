package com.example.smtu_mobile

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.AlarmClock
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var statusChannel: MethodChannel? = null

    /// Нажатие на уведомление о будильнике ещё не передано во Flutter:
    /// при холодном старте забирается методом `consumeOpenAlarms`.
    private var pendingOpenAlarms = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        pendingOpenAlarms = intent?.getBooleanExtra(
            AlarmStatusService.EXTRA_OPEN_ALARMS,
            false,
        ) == true

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "smtu/alarm_status",
        ).also { channel ->
            statusChannel = channel

            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "showAlarmStatus" -> {
                        val title = call.argument<String>("title") ?: "Будильник"
                        val body = call.argument<String>("body") ?: ""
                        val whenMillis = (call.argument<Number>("when"))?.toLong() ?: 0L

                        try {
                            AlarmStatusService.start(this, title, body, whenMillis)
                            result.success(true)
                        } catch (e: Exception) {
                            // Сервис запустить нельзя: Flutter покажет
                            // обычное уведомление.
                            result.success(false)
                        }
                    }
                    "hideAlarmStatus" -> {
                        AlarmStatusService.stop(this)
                        result.success(true)
                    }
                    "consumeOpenAlarms" -> {
                        val value = pendingOpenAlarms
                        pendingOpenAlarms = false
                        result.success(value)
                    }
                    else -> result.notImplemented()
                }
            }
        }

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
                "requestBackgroundPermission" -> {
                    result.success(requestBackgroundPermission())
                }
                "canScheduleExactAlarms" -> {
                    result.success(AlarmScheduler.canScheduleExact(this))
                }
                "requestExactAlarmPermission" -> {
                    result.success(requestExactAlarmPermission())
                }
                "cancelAlarms" -> {
                    try {
                        cancelAlarms()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error(
                            "cancel_failed",
                            "${e.javaClass.simpleName}: ${e.message}",
                            null,
                        )
                    }
                }
                "scheduleAlarms" -> {
                    val alarms = call.argument<List<Map<String, Any?>>>("alarms")
                        ?: emptyList()

                    try {
                        result.success(scheduleAlarms(alarms))
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

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)

        setIntent(intent)

        if (intent.getBooleanExtra(AlarmStatusService.EXTRA_OPEN_ALARMS, false)) {
            pendingOpenAlarms = true

            // Если Flutter уже запущен, открываем будильники сразу.
            statusChannel?.invokeMethod("openAlarms", null)
        }
    }

    /// Открывает настройки «Будильники и напоминания». Возвращает true,
    /// если разрешение на точные будильники уже выдано.
    private fun requestExactAlarmPermission(): Boolean {
        if (AlarmScheduler.canScheduleExact(this)) return true

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                startActivity(
                    Intent(
                        Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                        Uri.parse("package:$packageName"),
                    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
                return false
            } catch (_: Exception) {
                // На части прошивок такого экрана нет.
            }
        }

        try {
            startActivity(
                Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:$packageName"),
                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        } catch (_: Exception) {
            return false
        }

        return false
    }

    /// Открывает системный запрос на работу в фоне (исключение из
    /// оптимизации батареи). Возвращает true, если разрешение уже выдано.
    private fun requestBackgroundPermission(): Boolean {
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager

        if (powerManager.isIgnoringBatteryOptimizations(packageName)) {
            return true
        }

        // Сначала сам запрос исключения, если производитель его поддерживает.
        try {
            startActivity(
                Intent(
                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                    Uri.parse("package:$packageName"),
                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            return false
        } catch (_: Exception) {
            // Некоторые прошивки не умеют показывать запрос напрямую.
        }

        // Иначе открываем общий список приложений с исключениями.
        try {
            startActivity(
                Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        } catch (_: Exception) {
            return false
        }

        return false
    }

    /// Снимает все будильники приложения и забывает сохранённый план.
    private fun cancelAlarms() {
        AlarmScheduler.cancelAll(this)
        AlarmScheduler.save(this, emptyList())
    }

    private fun scheduleAlarms(alarms: List<Map<String, Any?>>): Boolean {
        val parsed = alarms.mapIndexedNotNull { index, alarm ->
            val triggerAt = (alarm["triggerAtMillis"] as? Number)?.toLong()
                ?: return@mapIndexedNotNull null

            AlarmScheduler.Alarm(
                id = (alarm["id"] as? Number)?.toInt() ?: index,
                triggerAtMillis = triggerAt,
                message = alarm["message"] as? String ?: "Пора на пару",
            )
        }

        return AlarmScheduler.schedule(this, parsed)
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
