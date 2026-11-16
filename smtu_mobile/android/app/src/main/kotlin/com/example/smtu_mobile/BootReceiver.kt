package com.example.smtu_mobile

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/// Android удаляет все будильники AlarmManager при выключении телефона.
/// После загрузки (и после обновления приложения) ставим их заново из
/// сохранённого плана.
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        when (intent?.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            "android.intent.action.QUICKBOOT_POWERON",
            "com.htc.intent.action.QUICKBOOT_POWERON",
            -> AlarmScheduler.rescheduleFromStorage(context)
        }
    }
}
