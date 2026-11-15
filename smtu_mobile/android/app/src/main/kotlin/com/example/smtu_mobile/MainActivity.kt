package com.example.smtu_mobile

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
                else -> result.notImplemented()
            }
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
