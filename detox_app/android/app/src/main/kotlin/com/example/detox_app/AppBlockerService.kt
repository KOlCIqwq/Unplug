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
                
                // Ignore popups, dialogs, menus, and bottom sheets.
                // These are just in-app overlays, not real app transitions.
                if (className.contains("dialog") || 
                    className.contains("popup") || 
                    className.contains("bottomsheet") || 
                    className.contains("menu") ||
                    className.startsWith("android.widget.") ||
                    className.startsWith("android.view.")) {
                    return
                }

                // 1. Build a list of packages to permanently ignore (keyboards, system ui, and our own app)
                if (ignoredPackages == null) {
                    val imm = getSystemService(android.content.Context.INPUT_METHOD_SERVICE) as android.view.inputmethod.InputMethodManager
                    val imes = imm.inputMethodList.map { it.packageName }.toMutableSet()
                    imes.add("com.android.systemui")
                    imes.add("android")
                    imes.add(this.packageName) // Ignore Detox app itself so it doesn't break transitions
                    ignoredPackages = imes
                }
                
                if (ignoredPackages?.contains(packageName) == true) {
                    return // Ignore keyboards and system UI, do nothing
                }

                // 2. Fetch launchers
                if (launcherPackages == null) {
                    val intent = Intent(Intent.ACTION_MAIN).apply { addCategory(Intent.CATEGORY_HOME) }
                    val resolveInfoList = packageManager.queryIntentActivities(intent, android.content.pm.PackageManager.MATCH_DEFAULT_ONLY)
                    launcherPackages = resolveInfoList.map { it.activityInfo.packageName }
                }

                // 3. Determine if this package is a real, user-facing app or the Home launcher.
                val isLauncher = launcherPackages?.contains(packageName) == true
                val hasLaunchIntent = packageManager.getLaunchIntentForPackage(packageName) != null
                
                if (!isLauncher && !hasLaunchIntent) {
                    return // Ignore non-apps entirely! They don't count as "leaving" the app.
                }

                // 4. Handle debounce for accidental transitions (like gesture nav or reaction popups)
                if (packageName == temporarilyAllowedPackage) {
                    if (leftAppTime != 0L) {
                        if (System.currentTimeMillis() - leftAppTime < 5000) {
                            // False alarm (e.g. gesture nav or quick popup). Restore session!
                            leftAppTime = 0L
                            return
                        } else {
                            // They actually left and came back later. Expire the session.
                            temporarilyAllowedPackage = null
                            leftAppTime = 0L
                        }
                    } else {
                        // Normal usage inside the app
                        return
                    }
                } else {
                    // They are looking at a different app/launcher. Start the leave timer.
                    if (temporarilyAllowedPackage != null && leftAppTime == 0L) {
                        leftAppTime = System.currentTimeMillis()
                    }
                }

                // 5. Check if this new app is a blocked app.
                val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
                val blockedAppsString = prefs.getString("flutter.blocked_apps_string", "")
                val blockedApps = blockedAppsString?.split(",")?.toSet() ?: emptySet()
                
                if (blockedApps.contains(packageName)) {
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
