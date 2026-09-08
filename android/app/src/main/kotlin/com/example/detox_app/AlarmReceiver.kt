package com.example.detox_app

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log

class AlarmReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "AlarmReceiver"
        const val ACTION_TRIGGER_ALARM = "com.example.detox_app.ACTION_TRIGGER_ALARM"
        const val ACTION_DISMISS_ALARM = "com.example.detox_app.ACTION_DISMISS_ALARM"
        const val ACTION_SNOOZE_ALARM = "com.example.detox_app.ACTION_SNOOZE_ALARM"

        const val EXTRA_ALARM_ID = "alarm_id"
        const val EXTRA_ALARM_TITLE = "alarm_title"
        const val CHANNEL_ID = "detox_alarm_channel"
        const val NOTIFICATION_ID = 2001

        private var ringtone: Ringtone? = null
        private var wakeLock: PowerManager.WakeLock? = null

        fun scheduleAlarm(context: Context, id: String, timestampMs: Long, title: String) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
            val intent = Intent(context, AlarmReceiver::class.java).apply {
                action = ACTION_TRIGGER_ALARM
                putExtra(EXTRA_ALARM_ID, id)
                putExtra(EXTRA_ALARM_TITLE, title)
            }
            val reqCode = id.hashCode()
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                reqCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    if (alarmManager.canScheduleExactAlarms()) {
                        alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, timestampMs, pendingIntent)
                    } else {
                        alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, timestampMs, pendingIntent)
                    }
                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, timestampMs, pendingIntent)
                } else {
                    alarmManager.setExact(AlarmManager.RTC_WAKEUP, timestampMs, pendingIntent)
                }
                Log.d(TAG, "Scheduled alarm $id for timestamp $timestampMs")
            } catch (e: Exception) {
                Log.e(TAG, "Error scheduling alarm", e)
                alarmManager.set(AlarmManager.RTC_WAKEUP, timestampMs, pendingIntent)
            }
        }

        fun cancelAlarm(context: Context, id: String) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
            val intent = Intent(context, AlarmReceiver::class.java).apply {
                action = ACTION_TRIGGER_ALARM
                putExtra(EXTRA_ALARM_ID, id)
            }
            val reqCode = id.hashCode()
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                reqCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            alarmManager.cancel(pendingIntent)
            Log.d(TAG, "Cancelled alarm $id")
        }

        fun startRinging(context: Context, title: String) {
            try {
                stopRinging(context)

                // Acquire WakeLock for 3 minutes max
                val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
                wakeLock = pm?.newWakeLock(
                    PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
                    "Unplug:AlarmWakeLock"
                )?.apply {
                    acquire(3 * 60 * 1000L)
                }

                // Play alarm ringtone
                var alertUri: Uri? = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                if (alertUri == null) {
                    alertUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                }
                if (alertUri == null) {
                    alertUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                }

                ringtone = RingtoneManager.getRingtone(context.applicationContext, alertUri)?.apply {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                        audioAttributes = AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_ALARM)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .build()
                    }
                    play()
                }

                // Vibrate
                startVibrating(context)
            } catch (e: Exception) {
                Log.e(TAG, "Error starting alarm ringing", e)
            }
        }

        fun stopRinging(context: Context) {
            try {
                ringtone?.stop()
                ringtone = null

                stopVibrating(context)

                if (wakeLock?.isHeld == true) {
                    wakeLock?.release()
                }
                wakeLock = null

                val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                nm?.cancel(NOTIFICATION_ID)
            } catch (e: Exception) {
                Log.e(TAG, "Error stopping ringing", e)
            }
        }

        private fun startVibrating(context: Context) {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    val vm = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                    val vibrator = vm?.defaultVibrator
                    val pattern = longArrayOf(0, 500, 200, 500, 200, 500)
                    vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0))
                } else {
                    @Suppress("DEPRECATION")
                    val vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
                    val pattern = longArrayOf(0, 500, 200, 500, 200, 500)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0))
                    } else {
                        @Suppress("DEPRECATION")
                        vibrator?.vibrate(pattern, 0)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error starting vibration", e)
            }
        }

        private fun stopVibrating(context: Context) {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    val vm = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                    vm?.defaultVibrator?.cancel()
                } else {
                    @Suppress("DEPRECATION")
                    val vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
                    vibrator?.cancel()
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error stopping vibration", e)
            }
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        val alarmId = intent.getStringExtra(EXTRA_ALARM_ID) ?: "default_alarm"
        val title = intent.getStringExtra(EXTRA_ALARM_TITLE) ?: "Alarm"

        when (intent.action) {
            ACTION_TRIGGER_ALARM -> {
                Log.d(TAG, "Triggering alarm: $title ($alarmId)")
                startRinging(context, title)
                showAlarmNotification(context, alarmId, title)

                // Jump directly to app! First via active AccessibilityService, fallback to standard context
                val jumpedViaA11y = AppBlockerService.launchAlarmScreen(alarmId, title)
                if (!jumpedViaA11y) {
                    try {
                        val launchIntent = Intent(context, MainActivity::class.java).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
                            putExtra("is_alarm_ringing", true)
                            putExtra("alarm_id", alarmId)
                            putExtra("alarm_title", title)
                        }
                        context.startActivity(launchIntent)
                    } catch (e: Exception) {
                        Log.w(TAG, "Fallback standard activity launch failed", e)
                    }
                }
            }
            ACTION_DISMISS_ALARM -> {
                Log.d(TAG, "Dismissing alarm: $alarmId")
                stopRinging(context)
            }
            ACTION_SNOOZE_ALARM -> {
                Log.d(TAG, "Snoozing alarm: $alarmId")
                stopRinging(context)
                val snoozeMs = System.currentTimeMillis() + (5 * 60 * 1000L)
                scheduleAlarm(context, "${alarmId}_snooze", snoozeMs, "Snooze: $title")
            }
        }
    }

    private fun showAlarmNotification(context: Context, alarmId: String, title: String) {
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Alarms",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Unplug high-priority alarms"
                enableVibration(true)
                setSound(null, null) // Sound is handled by RingtoneManager
            }
            notificationManager.createNotificationChannel(channel)
        }

        // Tap notification intent (opens MainActivity to ringing screen)
        val fullScreenIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("is_alarm_ringing", true)
            putExtra("alarm_id", alarmId)
            putExtra("alarm_title", title)
        }
        val fullScreenPendingIntent = PendingIntent.getActivity(
            context,
            3001,
            fullScreenIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Dismiss action intent
        val dismissIntent = Intent(context, AlarmReceiver::class.java).apply {
            action = ACTION_DISMISS_ALARM
            putExtra(EXTRA_ALARM_ID, alarmId)
        }
        val dismissPendingIntent = PendingIntent.getBroadcast(
            context,
            3002,
            dismissIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Snooze action intent
        val snoozeIntent = Intent(context, AlarmReceiver::class.java).apply {
            action = ACTION_SNOOZE_ALARM
            putExtra(EXTRA_ALARM_ID, alarmId)
            putExtra(EXTRA_ALARM_TITLE, title)
        }
        val snoozePendingIntent = PendingIntent.getBroadcast(
            context,
            3003,
            snoozeIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val smallIconRes = context.applicationInfo.icon.takeIf { it != 0 } ?: android.R.drawable.ic_lock_idle_alarm

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }

        builder.apply {
            setContentTitle("ALARM: $title")
            setContentText("Tap to dismiss or snooze")
            setSmallIcon(smallIconRes)
            setContentIntent(fullScreenPendingIntent)
            setFullScreenIntent(fullScreenPendingIntent, true)
            setOngoing(true)
            setAutoCancel(false)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT_WATCH) {
                addAction(
                    Notification.Action.Builder(
                        null,
                        "Dismiss",
                        dismissPendingIntent
                    ).build()
                )
                addAction(
                    Notification.Action.Builder(
                        null,
                        "Snooze (5m)",
                        snoozePendingIntent
                    ).build()
                )
            }
        }

        notificationManager.notify(NOTIFICATION_ID, builder.build())
    }
}
