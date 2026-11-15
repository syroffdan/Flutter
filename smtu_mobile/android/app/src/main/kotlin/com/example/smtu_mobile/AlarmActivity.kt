package com.example.smtu_mobile

import android.app.Activity
import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.view.Gravity
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/// Экран будильника: показывается поверх блокировки, играет звук и вибрирует.
class AlarmActivity : Activity() {
    private var player: MediaPlayer? = null
    private var vibrator: Vibrator? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
            )
        }

        val message = intent.getStringExtra("message") ?: "Пора на пару"

        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(0xFF0E1B2A.toInt())
            setPadding(64, 96, 64, 96)
        }

        layout.addView(
            TextView(this).apply {
                text = "БУДИЛЬНИК"
                textSize = 16f
                gravity = Gravity.CENTER
                setTextColor(0xFF9FB3C8.toInt())
            },
        )

        layout.addView(
            TextView(this).apply {
                text = message
                textSize = 28f
                gravity = Gravity.CENTER
                setTextColor(0xFFFFFFFF.toInt())
                setPadding(0, 32, 0, 64)
            },
        )

        layout.addView(
            Button(this).apply {
                text = "Отключить"
                textSize = 20f
                setOnClickListener {
                    stopAlarm()
                    finish()
                }
            },
        )

        setContentView(layout)

        startSound()
        startVibration()
    }

    private fun startSound() {
        try {
            val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)

            val attributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()

            player = MediaPlayer().apply {
                setAudioAttributes(attributes)
                setDataSource(this@AlarmActivity, uri)
                isLooping = true
                prepare()
                start()
            }
        } catch (_: Exception) {
            // Если звук недоступен, остаётся вибрация и экран.
        }
    }

    private fun startVibration() {
        try {
            vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator

            val pattern = longArrayOf(0, 800, 800)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator?.vibrate(
                    VibrationEffect.createWaveform(pattern, 0),
                )
            } else {
                @Suppress("DEPRECATION")
                vibrator?.vibrate(pattern, 0)
            }
        } catch (_: Exception) {
            // Вибрация может быть запрещена настройками устройства.
        }
    }

    private fun stopAlarm() {
        try {
            player?.stop()
            player?.release()
        } catch (_: Exception) {
        }
        player = null

        try {
            vibrator?.cancel()
        } catch (_: Exception) {
        }
        vibrator = null
    }

    override fun onDestroy() {
        stopAlarm()
        super.onDestroy()
    }
}
