package com.example.detox_app

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.view.accessibility.AccessibilityEvent
import android.util.Log

class AppBlockerService : AccessibilityService() {
    private val TAG = "AppBlockerService"

    companion object {
        var temporarilyAllowedPackage: String? = null
        var launcherPackages: List<String>? = null
        var ignoredPackages: Set<String>? = null
        var leftAppTime: Long = 0L
        
        fun allowApp(packageName: String) {
            temporarilyAllowedPackage = packageName
            leftAppTime = 0L
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        try {
            if (event == null) return
            
            if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
                val packageName = event.packageName?.toString() ?: return
                val className = event.className?.toString()?.lowercase() ?: ""
                
                if (className.contains("dialog") || 
                    className.contains("popup") || 
                    className.contains("bottomsheet") || 
                    className.contains("menu") ||
                    className.startsWith("android.widget.") ||
                    className.startsWith("android.view.")) {
                    return
                }

                if (ignoredPackages == null) {
                    val imm = getSystemService(android.content.Context.INPUT_METHOD_SERVICE) as android.view.inputmethod.InputMethodManager
                    val imes = imm.inputMethodList.map { it.packageName }.toMutableSet()
                    imes.add("com.android.systemui")
                    imes.add("android")
                    imes.add(this.packageName) 
                    ignoredPackages = imes
                }
                
                if (ignoredPackages?.contains(packageName) == true) {
                    return 
                }

                val rootPackage = rootInActiveWindow?.packageName?.toString() ?: packageName
                val effectivePackage = if (rootPackage == temporarilyAllowedPackage) rootPackage else packageName

                val isLauncher = launcherPackages?.contains(effectivePackage) == true || run {
                    val intent = Intent(Intent.ACTION_MAIN).apply { addCategory(Intent.CATEGORY_HOME) }
                    val resolveInfoList = packageManager.queryIntentActivities(intent, android.content.pm.PackageManager.MATCH_DEFAULT_ONLY)
                    val launchers = resolveInfoList.map { it.activityInfo.packageName }
                    launcherPackages = launchers
                    launchers.contains(effectivePackage)
                }
                
                val hasLaunchIntent = packageManager.getLaunchIntentForPackage(effectivePackage) != null
                
                if (!isLauncher && !hasLaunchIntent) {
                    return 
                }

                if (effectivePackage == temporarilyAllowedPackage) {
                    if (leftAppTime != 0L) {
                        if (System.currentTimeMillis() - leftAppTime < 5000) {
                            leftAppTime = 0L
                            return
                        } else {
                            temporarilyAllowedPackage = null
                            leftAppTime = 0L
                        }
                    } else {
                        return
                    }
                } else {
                    if (temporarilyAllowedPackage != null && leftAppTime == 0L) {
                        leftAppTime = System.currentTimeMillis()
                    }
                }

                val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
                val blockedAppsString = prefs.getString("flutter.blocked_apps_string", "")
                val blockedApps = blockedAppsString?.split(",")?.toSet() ?: emptySet()
                
                if (blockedApps.contains(effectivePackage)) {
                    Log.d(TAG, "Blocked app launched: $effectivePackage")
                    
                    // Increment resist count immediately so app termination or home navigation is captured
                    val currentCount = prefs.getInt("flutter.cancel_count", 0)
                    prefs.edit().putInt("flutter.cancel_count", currentCount + 1).apply()

                    val launchIntent = Intent(this, MainActivity::class.java).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                        putExtra("blocked_package", effectivePackage)
                        putExtra("debug_info", "EventPkg: $packageName | Class: $className | RootPkg: $rootPackage")
                    }
                    startActivity(launchIntent)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error in AccessibilityService", e)
        }
    }

    override fun onInterrupt() {}
}
