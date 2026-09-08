package com.example.detox_app

import android.app.PendingIntent
import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.detox_app/intervention"
    private var blockedPackageIntent: String? = null
    private var debugInfoIntent: String? = null
    private var isZenBlockIntent: Boolean = false
    private var isLimitBlockIntent: Boolean = false
    private var usedMinutesIntent: Int = 0
    private var limitMinutesIntent: Int = 0
    private var pendingAlarmId: String? = null
    private var pendingAlarmTitle: String? = null
    private var pendingOpenAssignTask: Boolean = false

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }
        @Suppress("DEPRECATION")
        window.addFlags(
            android.view.WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
            android.view.WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
            android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
            android.view.WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
        )
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            if (checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 1002)
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getPendingIntervention" -> {
                    val map = mapOf(
                        "package" to blockedPackageIntent,
                        "debug" to debugInfoIntent,
                        "isZenBlock" to isZenBlockIntent,
                        "isLimitBlock" to isLimitBlockIntent,
                        "usedMinutes" to usedMinutesIntent,
                        "limitMinutes" to limitMinutesIntent
                    )
                    result.success(map)
                    blockedPackageIntent = null 
                    debugInfoIntent = null
                    isZenBlockIntent = false
                    isLimitBlockIntent = false
                    usedMinutesIntent = 0
                    limitMinutesIntent = 0
                }
                "openAccessibilitySettings" -> {
                    val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                    startActivity(intent)
                    result.success(true)
                }
                "allowAppTemporarily" -> {
                    val args = call.arguments as? Map<*, *>
                    val packageName = args?.get("package") as? String ?: call.arguments as? String
                    val durationMinutes = (args?.get("durationMinutes") as? Number)?.toInt() ?: 5

                    if (packageName != null) {
                        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)

                        var effectiveDurationMinutes = durationMinutes
                        val limitMins = AppBlockerService.getSafeInt(prefs, "flutter.limit_$packageName", 0)
                        val dateKey = AppBlockerService.getTodayDateKey()
                        val usedMs = AppBlockerService.getSafeLong(prefs, "flutter.usage_${dateKey}_$packageName", 0L)
                        val usedMins = (usedMs / (60 * 1000)).toInt()

                        if (limitMins > 0) {
                            val remainingMins = limitMins - usedMins
                            if (remainingMins in 1 until effectiveDurationMinutes) {
                                effectiveDurationMinutes = remainingMins
                            }
                        }

                        val durationMs = effectiveDurationMinutes.toLong() * 60L * 1000L
                        AppBlockerService.allowApp(this@MainActivity, packageName, durationMs)
                        
                        blockedPackageIntent = null
                        debugInfoIntent = null
                        isZenBlockIntent = false

                        // Launch the target app natively for reliability
                        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
                        if (launchIntent != null) {
                            launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(launchIntent)
                        }
                        moveTaskToBack(true)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARG", "Package name is null", null)
                    }
                }
                "goHome" -> {
                    val homeIntent = Intent(Intent.ACTION_MAIN).apply {
                        addCategory(Intent.CATEGORY_HOME)
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                    startActivity(homeIntent)
                    result.success(true)
                }
                "updateZenWidget" -> {
                    ZenWidgetProvider.updateAllWidgets(this@MainActivity)
                    result.success(true)
                }
                "scheduleAlarm" -> {
                    val args = call.arguments as? Map<*, *>
                    val id = args?.get("id") as? String ?: ""
                    val timestamp = (args?.get("timestamp") as? Number)?.toLong() ?: 0L
                    val title = args?.get("title") as? String ?: "Alarm"
                    if (id.isNotEmpty() && timestamp > 0L) {
                        AlarmReceiver.scheduleAlarm(this@MainActivity, id, timestamp, title)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGS", "Missing id or timestamp", null)
                    }
                }
                "cancelAlarm" -> {
                    val args = call.arguments as? Map<*, *>
                    val id = args?.get("id") as? String ?: call.arguments as? String ?: ""
                    if (id.isNotEmpty()) {
                        AlarmReceiver.cancelAlarm(this@MainActivity, id)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGS", "Missing id", null)
                    }
                }
                "startAlarmRinging" -> {
                    val args = call.arguments as? Map<*, *>
                    val title = args?.get("title") as? String ?: "Alarm"
                    AlarmReceiver.startRinging(this@MainActivity, title)
                    result.success(true)
                }
                "stopAlarmRinging" -> {
                    AlarmReceiver.stopRinging(this@MainActivity)
                    result.success(true)
                }
                "getPendingAlarm" -> {
                    val map = if (pendingAlarmId != null) {
                        mapOf("alarmId" to pendingAlarmId, "title" to pendingAlarmTitle)
                    } else {
                        null
                    }
                    pendingAlarmId = null
                    pendingAlarmTitle = null
                    result.success(map)
                }
                "getPendingAssignTask" -> {
                    val value = pendingOpenAssignTask
                    pendingOpenAssignTask = false
                    result.success(value)
                }
                "isDndPermissionGranted" -> {
                    result.success(ZenDndManager.isDndPermissionGranted(this@MainActivity))
                }
                "openDndSettings" -> {
                    ZenDndManager.openDndSettings(this@MainActivity)
                    result.success(true)
                }
                "enableZenSilence" -> {
                    ZenDndManager.enableZenSilence(this@MainActivity)
                    result.success(true)
                }
                "disableZenSilence" -> {
                    ZenDndManager.disableZenSilence(this@MainActivity)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    override fun onResume() {
        super.onResume()
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent) {
        val isAlarmRinging = intent.getBooleanExtra("is_alarm_ringing", false)
        val alarmId = intent.getStringExtra("alarm_id")
        val alarmTitle = intent.getStringExtra("alarm_title")
        if (isAlarmRinging && alarmId != null) {
            pendingAlarmId = alarmId
            pendingAlarmTitle = alarmTitle
            flutterEngine?.dartExecutor?.binaryMessenger?.let {
                MethodChannel(it, CHANNEL).invokeMethod("triggerAlarm", mapOf(
                    "alarmId" to alarmId,
                    "title" to (alarmTitle ?: "Alarm")
                ))
            }
            intent.removeExtra("is_alarm_ringing")
            intent.removeExtra("alarm_id")
            intent.removeExtra("alarm_title")
        }

        val openAssignTask = intent.getBooleanExtra("open_assign_task", false)
        if (openAssignTask) {
            pendingOpenAssignTask = true
            flutterEngine?.dartExecutor?.binaryMessenger?.let {
                MethodChannel(it, CHANNEL).invokeMethod("openTaskPicker", null)
            }
            intent.removeExtra("open_assign_task")
        }

        val blockedPackage = intent.getStringExtra("blocked_package")
        val debugInfo = intent.getStringExtra("debug_info")
        val isZen = intent.getBooleanExtra("is_zen_block", false)
        val isLimitFromIntent = intent.getBooleanExtra("is_limit_block", false)
        val usedMinsFromIntent = intent.getIntExtra("used_minutes", 0)
        val limitMinsFromIntent = intent.getIntExtra("limit_minutes", 0)

        if (blockedPackage != null) {
            val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
            val dateKey = AppBlockerService.getTodayDateKey()
            val usedMs = AppBlockerService.getSafeLong(prefs, "flutter.usage_${dateKey}_$blockedPackage", 0L)
            val limitMinsFromPrefs = AppBlockerService.getSafeInt(prefs, "flutter.limit_$blockedPackage", 0)
            val usedMinsCalculated = (usedMs / (60 * 1000)).toInt()

            val effectiveLimitMins = if (limitMinsFromIntent > 0) limitMinsFromIntent else limitMinsFromPrefs
            val effectiveUsedMins = if (usedMinsFromIntent > 0) usedMinsFromIntent else usedMinsCalculated
            val effectiveIsLimit = isLimitFromIntent || (effectiveLimitMins > 0 && effectiveUsedMins >= effectiveLimitMins)

            blockedPackageIntent = blockedPackage
            debugInfoIntent = debugInfo
            isZenBlockIntent = isZen
            isLimitBlockIntent = effectiveIsLimit
            usedMinutesIntent = effectiveUsedMins
            limitMinutesIntent = effectiveLimitMins
            
            flutterEngine?.dartExecutor?.binaryMessenger?.let {
                val map = mapOf(
                    "package" to blockedPackage,
                    "debug" to debugInfo,
                    "isZenBlock" to isZen,
                    "isLimitBlock" to effectiveIsLimit,
                    "usedMinutes" to effectiveUsedMins,
                    "limitMinutes" to effectiveLimitMins
                )
                MethodChannel(it, CHANNEL).invokeMethod("triggerIntervention", map)
            }
            intent.removeExtra("blocked_package")
            intent.removeExtra("debug_info")
            intent.removeExtra("is_zen_block")
            intent.removeExtra("is_limit_block")
            intent.removeExtra("used_minutes")
            intent.removeExtra("limit_minutes")
        }
    }
}
