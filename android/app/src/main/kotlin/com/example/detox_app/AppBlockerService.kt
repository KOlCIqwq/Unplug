package com.example.detox_app

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.view.accessibility.AccessibilityEvent
import android.util.Log

class AppBlockerService : AccessibilityService() {
    private val TAG = "AppBlockerService"

    companion object {
        var temporarilyAllowedPackage: String? = null
        var allowedUntil: Long = 0L
        var lastForegroundPackage: String? = null
        var launcherPackages: List<String>? = null
        var ignoredPackages: Set<String>? = null
        
        fun allowApp(packageName: String, durationMs: Long = 3000) { // 3 seconds grace period just for the launch transition
            temporarilyAllowedPackage = packageName
            allowedUntil = System.currentTimeMillis() + durationMs
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        try {
            if (event == null) return
            
            if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
                val packageName = event.packageName?.toString() ?: return
                
                // Build a list of packages to permanently ignore (keyboards, system ui)
                if (ignoredPackages == null) {
                    val imm = getSystemService(android.content.Context.INPUT_METHOD_SERVICE) as android.view.inputmethod.InputMethodManager
                    val imes = imm.inputMethodList.map { it.packageName }.toMutableSet()
                    imes.add("com.android.systemui")
                    imes.add("android")
                    ignoredPackages = imes
                }
                
                if (ignoredPackages?.contains(packageName) == true) {
                    return // Ignore keyboards and system UI
                }

                // Determine if this package is a real, user-facing app or the Home launcher.
                // This globally filters out hidden OS services, popups, and the notification shade
                // that briefly steal focus and mess up our tracking.
                val isLauncher = launcherPackages?.contains(packageName) == true || run {
                    val intent = Intent(Intent.ACTION_MAIN).apply { addCategory(Intent.CATEGORY_HOME) }
                    val resolveInfoList = packageManager.queryIntentActivities(intent, android.content.pm.PackageManager.MATCH_DEFAULT_ONLY)
                    val launchers = resolveInfoList.map { it.activityInfo.packageName }
                    launcherPackages = launchers
                    launchers.contains(packageName)
                }
                
                val hasLaunchIntent = packageManager.getLaunchIntentForPackage(packageName) != null
                
                if (!isLauncher && !hasLaunchIntent) {
                    return // Ignore non-apps entirely!
                }

                // If the app is already in the foreground, this is just an internal navigation event.
                // We only care when the foreground package *changes*.
                if (packageName == lastForegroundPackage) {
                    return
                }
                
                lastForegroundPackage = packageName
                
                // Read blocked apps from SharedPreferences using the simple string format
                val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
                val blockedAppsString = prefs.getString("flutter.blocked_apps_string", "")
                val blockedApps = blockedAppsString?.split(",")?.toSet() ?: emptySet()
                
                if (blockedApps.contains(packageName)) {
                    // Check if the user just waited for the timer for this app
                    if (packageName == temporarilyAllowedPackage && System.currentTimeMillis() < allowedUntil) {
                        return // Let them use the app!
                    }

                    Log.d(TAG, "Blocked app launched: $packageName")
                    
                    // Launch our Flutter MainActivity over the top
                    val launchIntent = Intent(this, MainActivity::class.java).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                        putExtra("blocked_package", packageName)
                    }
                    startActivity(launchIntent)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error in AccessibilityService", e)
        }
    }

    override fun onInterrupt() {
        // Required, but we don't need to do anything here
    }
}
