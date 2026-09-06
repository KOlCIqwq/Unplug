package com.example.detox_app

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.View
import android.widget.RemoteViews

class ZenWidgetProvider : AppWidgetProvider() {

    companion object {
        private const val TAG = "ZenWidgetProvider"
        const val ACTION_START_ZEN = "com.example.detox_app.ACTION_START_ZEN"
        const val ACTION_TAP_OUTLET = "com.example.detox_app.ACTION_TAP_OUTLET"
        const val ACTION_ADD_TIME = "com.example.detox_app.ACTION_ADD_TIME"
        const val ACTION_STOP_ZEN = "com.example.detox_app.ACTION_STOP_ZEN"
        const val ACTION_ZEN_EXPIRED = "com.example.detox_app.ACTION_ZEN_EXPIRED"
        const val EXTRA_MINUTES = "extra_minutes"

        private const val REQ_LAUNCH = 100
        private const val REQ_TAP_OUTLET = 101
        private const val REQ_START_15 = 102
        private const val REQ_START_30 = 103
        private const val REQ_START_60 = 104
        private const val REQ_CLOSE = 105
        private const val REQ_SOCKET_PLUG_BACK = 106
        private const val REQ_ADD_15 = 107
        private const val REQ_STOP = 108
        private const val REQ_EXPIRED = 200

        fun updateAllWidgets(context: Context) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val thisWidget = ComponentName(context, ZenWidgetProvider::class.java)
            val appWidgetIds = appWidgetManager.getAppWidgetIds(thisWidget)
            if (appWidgetIds != null && appWidgetIds.isNotEmpty()) {
                for (appWidgetId in appWidgetIds) {
                    updateAppWidget(context, appWidgetManager, appWidgetId)
                }
            }
        }

        fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val zenEndTime = AppBlockerService.getSafeLong(prefs, "flutter.zen_mode_end_time", 0L)
            val now = System.currentTimeMillis()
            val isZenActive = zenEndTime > now

            val views = RemoteViews(context.packageName, R.layout.zen_widget)
            views.setViewVisibility(R.id.layout_zen_animating, View.GONE)

            if (isZenActive) {
                // STATE 2: ACTIVE
                views.setViewVisibility(R.id.layout_zen_idle, View.GONE)
                views.setViewVisibility(R.id.layout_zen_active, View.VISIBLE)

                // Chronometer countdown positioned inside the head loop
                val remainingMs = zenEndTime - now
                val base = SystemClock.elapsedRealtime() + remainingMs
                views.setChronometer(R.id.zen_chronometer, base, null, true)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    views.setChronometerCountDown(R.id.zen_chronometer, true)
                }

                // Tapping ON badge triggers plug back in animation & exit
                views.setOnClickPendingIntent(R.id.btn_status_on, createBroadcastPendingIntent(context, ACTION_STOP_ZEN, 0, REQ_CLOSE))

                // Tapping unplugged illustration triggers plug back in animation & exit
                views.setOnClickPendingIntent(R.id.img_state_on, createBroadcastPendingIntent(context, ACTION_STOP_ZEN, 0, REQ_SOCKET_PLUG_BACK))

                // +15m button to add time to zen clock
                views.setOnClickPendingIntent(R.id.btn_add_15, createBroadcastPendingIntent(context, ACTION_ADD_TIME, 15, REQ_ADD_15))

                // End Zen button
                views.setOnClickPendingIntent(R.id.btn_stop_zen, createBroadcastPendingIntent(context, ACTION_STOP_ZEN, 0, REQ_STOP))

            } else {
                // STATE 1: IDLE / OFF
                views.setViewVisibility(R.id.layout_zen_idle, View.VISIBLE)
                views.setViewVisibility(R.id.layout_zen_active, View.GONE)
                views.setChronometer(R.id.zen_chronometer, SystemClock.elapsedRealtime(), null, false)

                // Tapping header opens the main app
                val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: Intent(context, MainActivity::class.java)
                launchIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                views.setOnClickPendingIntent(
                    R.id.widget_header_idle,
                    PendingIntent.getActivity(context, REQ_LAUNCH, launchIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                )

                // Tapping OFF status badge or plugged illustration triggers unplug animation with last used duration
                views.setOnClickPendingIntent(R.id.btn_status_off, createBroadcastPendingIntent(context, ACTION_TAP_OUTLET, 0, REQ_TAP_OUTLET))
                views.setOnClickPendingIntent(R.id.img_state_off, createBroadcastPendingIntent(context, ACTION_TAP_OUTLET, 0, REQ_TAP_OUTLET))

                // Duration preset buttons (15m, 30m, 60m)
                views.setOnClickPendingIntent(R.id.btn_start_15, createBroadcastPendingIntent(context, ACTION_START_ZEN, 15, REQ_START_15))
                views.setOnClickPendingIntent(R.id.btn_start_30, createBroadcastPendingIntent(context, ACTION_START_ZEN, 30, REQ_START_30))
                views.setOnClickPendingIntent(R.id.btn_start_60, createBroadcastPendingIntent(context, ACTION_START_ZEN, 60, REQ_START_60))
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }

        private fun createBroadcastPendingIntent(context: Context, actionStr: String, minutes: Int, reqCode: Int): PendingIntent {
            val intent = Intent(context, ZenWidgetProvider::class.java).apply {
                action = actionStr
                if (minutes > 0) {
                    putExtra(EXTRA_MINUTES, minutes)
                }
            }
            return PendingIntent.getBroadcast(
                context,
                reqCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        private fun animateFrameSequence(context: Context, isForward: Boolean, onComplete: () -> Unit) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val thisWidget = ComponentName(context, ZenWidgetProvider::class.java)
            val appWidgetIds = appWidgetManager.getAppWidgetIds(thisWidget) ?: return
            if (appWidgetIds.isEmpty()) {
                onComplete()
                return
            }

            val frames = if (isForward) {
                intArrayOf(R.drawable.zen_plug_frame_1, R.drawable.zen_plug_frame_2, R.drawable.zen_plug_frame_3)
            } else {
                intArrayOf(R.drawable.zen_plug_frame_3, R.drawable.zen_plug_frame_2, R.drawable.zen_plug_frame_1)
            }

            val handler = Handler(Looper.getMainLooper())

            fun showFrame(frameRes: Int) {
                for (id in appWidgetIds) {
                    val views = RemoteViews(context.packageName, R.layout.zen_widget)
                    views.setViewVisibility(R.id.layout_zen_idle, View.GONE)
                    views.setViewVisibility(R.id.layout_zen_active, View.GONE)
                    views.setViewVisibility(R.id.layout_zen_animating, View.VISIBLE)
                    views.setImageViewResource(R.id.img_zen_anim, frameRes)
                    appWidgetManager.updateAppWidget(id, views)
                }
            }

            // Frame 0
            showFrame(frames[0])

            // Frame 1
            handler.postDelayed({
                showFrame(frames[1])
            }, 90)

            // Frame 2
            handler.postDelayed({
                showFrame(frames[2])
            }, 180)

            // Complete
            handler.postDelayed({
                onComplete()
            }, 280)
        }

        private fun scheduleZenExpirationAlarm(context: Context, endTime: Long) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
            val expireIntent = Intent(context, ZenWidgetProvider::class.java).apply {
                action = ACTION_ZEN_EXPIRED
            }
            val pendingExpire = PendingIntent.getBroadcast(
                context,
                REQ_EXPIRED,
                expireIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    if (alarmManager.canScheduleExactAlarms()) {
                        alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, endTime, pendingExpire)
                    } else {
                        alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, endTime, pendingExpire)
                    }
                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, endTime, pendingExpire)
                } else {
                    alarmManager.setExact(AlarmManager.RTC_WAKEUP, endTime, pendingExpire)
                }
            } catch (e: Exception) {
                Log.w(TAG, "Failed to schedule exact alarm, falling back to standard alarm", e)
                alarmManager.set(AlarmManager.RTC_WAKEUP, endTime, pendingExpire)
            }
        }

        private fun cancelZenExpirationAlarm(context: Context) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
            val expireIntent = Intent(context, ZenWidgetProvider::class.java).apply {
                action = ACTION_ZEN_EXPIRED
            }
            val pendingExpire = PendingIntent.getBroadcast(
                context,
                REQ_EXPIRED,
                expireIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            alarmManager.cancel(pendingExpire)
        }
    }

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)

        when (intent.action) {
            ACTION_START_ZEN -> {
                val minutes = intent.getIntExtra(EXTRA_MINUTES, 15)
                val endTime = System.currentTimeMillis() + (minutes * 60 * 1000L)
                val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                prefs.edit()
                    .putLong("flutter.zen_mode_end_time", endTime)
                    .putInt("flutter.zen_last_selected_minutes", minutes)
                    .apply()
                scheduleZenExpirationAlarm(context, endTime)

                val pendingResult = goAsync()
                animateFrameSequence(context, isForward = true) {
                    updateAllWidgets(context)
                    try { pendingResult.finish() } catch (_: Exception) {}
                }
            }
            ACTION_TAP_OUTLET -> {
                val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val lastMinutes = AppBlockerService.getSafeInt(prefs, "flutter.zen_last_selected_minutes", 15)
                val effectiveMinutes = if (lastMinutes > 0) lastMinutes else 15
                val endTime = System.currentTimeMillis() + (effectiveMinutes * 60 * 1000L)
                prefs.edit().putLong("flutter.zen_mode_end_time", endTime).apply()
                scheduleZenExpirationAlarm(context, endTime)

                val pendingResult = goAsync()
                animateFrameSequence(context, isForward = true) {
                    updateAllWidgets(context)
                    try { pendingResult.finish() } catch (_: Exception) {}
                }
            }
            ACTION_ADD_TIME -> {
                val minutes = intent.getIntExtra(EXTRA_MINUTES, 15)
                val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val currentEnd = AppBlockerService.getSafeLong(prefs, "flutter.zen_mode_end_time", 0L)
                val now = System.currentTimeMillis()
                val baseTime = if (currentEnd > now) currentEnd else now
                val newEndTime = baseTime + (minutes * 60 * 1000L)
                prefs.edit().putLong("flutter.zen_mode_end_time", newEndTime).apply()
                scheduleZenExpirationAlarm(context, newEndTime)
                updateAllWidgets(context)
            }
            ACTION_STOP_ZEN -> {
                val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                prefs.edit().putLong("flutter.zen_mode_end_time", 0L).apply()
                cancelZenExpirationAlarm(context)

                val pendingResult = goAsync()
                animateFrameSequence(context, isForward = false) {
                    updateAllWidgets(context)
                    try { pendingResult.finish() } catch (_: Exception) {}
                }
            }
            ACTION_ZEN_EXPIRED -> {
                val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val currentEnd = AppBlockerService.getSafeLong(prefs, "flutter.zen_mode_end_time", 0L)
                if (System.currentTimeMillis() >= currentEnd) {
                    prefs.edit().putLong("flutter.zen_mode_end_time", 0L).apply()
                }
                updateAllWidgets(context)
            }
        }
    }
}
