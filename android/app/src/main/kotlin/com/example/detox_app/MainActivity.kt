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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getPendingIntervention" -> {
                    val map = mapOf(
                        "package" to blockedPackageIntent,
                        "debug" to debugInfoIntent
                    )
                    result.success(map)
                    blockedPackageIntent = null 
                    debugInfoIntent = null
                }
                "openAccessibilitySettings" -> {
                    val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                    startActivity(intent)
                    result.success(true)
                }
                "allowAppTemporarily" -> {
                    val packageName = call.arguments as String?
                    if (packageName != null) {
                        // User proceeded; revert the optimistic resist increment
                        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
                        val currentCount = prefs.getInt("flutter.cancel_count", 0)
                        if (currentCount > 0) {
                            prefs.edit().putInt("flutter.cancel_count", currentCount - 1).apply()
                        }

                        AppBlockerService.allowApp(packageName)
                        
                        // Launch the target app natively for reliability
                        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
                        if (launchIntent != null) {
                            launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(launchIntent)
                        }
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
        if (blockedPackage != null) {
            blockedPackageIntent = blockedPackage
            debugInfoIntent = debugInfo
            
            flutterEngine?.dartExecutor?.binaryMessenger?.let {
                val map = mapOf("package" to blockedPackage, "debug" to debugInfo)
                MethodChannel(it, CHANNEL).invokeMethod("triggerIntervention", map)
            }
            intent.removeExtra("blocked_package")
            intent.removeExtra("debug_info")
        }
    }
}
