package com.example.detox_app

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

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
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
        val blockedPackage = intent.getStringExtra("blocked_package")
        val debugInfo = intent.getStringExtra("debug_info")
        val isZen = intent.getBooleanExtra("is_zen_block", false)
        val isLimit = intent.getBooleanExtra("is_limit_block", false)
        val usedMins = intent.getIntExtra("used_minutes", 0)
        val limitMins = intent.getIntExtra("limit_minutes", 0)

        if (blockedPackage != null) {
            blockedPackageIntent = blockedPackage
            debugInfoIntent = debugInfo
            isZenBlockIntent = isZen
            isLimitBlockIntent = isLimit
            usedMinutesIntent = usedMins
            limitMinutesIntent = limitMins
            
            flutterEngine?.dartExecutor?.binaryMessenger?.let {
                val map = mapOf(
                    "package" to blockedPackage,
                    "debug" to debugInfo,
                    "isZenBlock" to isZen,
                    "isLimitBlock" to isLimit,
                    "usedMinutes" to usedMins,
                    "limitMinutes" to limitMins
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
