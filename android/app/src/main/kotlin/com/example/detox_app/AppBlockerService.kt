package com.example.detox_app

import android.accessibilityservice.AccessibilityService
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.view.accessibility.AccessibilityEvent
import android.util.Log

class AppBlockerService : AccessibilityService() {
    private val TAG = "AppBlockerService"

    companion object {
        private const val NOTIFICATION_CHANNEL_ID = "detox_session_channel"
        private const val NOTIFICATION_ID = 1001

        var temporarilyAllowedPackage: String? = null
        var launcherPackages: List<String>? = null
        var ignoredPackages: Set<String>? = null
        var sessionExpirationTime: Long = 0L
        var hasEnteredAllowedApp: Boolean = false
        var sessionStartTime: Long = 0L
        private val sessionHandler = android.os.Handler(android.os.Looper.getMainLooper())
        
        fun allowApp(context: android.content.Context, packageName: String, durationMs: Long) {
            temporarilyAllowedPackage = packageName
            hasEnteredAllowedApp = false
            sessionStartTime = System.currentTimeMillis()
            sessionExpirationTime = System.currentTimeMillis() + durationMs

            val appLabel = try {
                val appInfo = context.packageManager.getApplicationInfo(packageName, 0)
                context.packageManager.getApplicationLabel(appInfo).toString()
            } catch (e: Exception) {
                packageName
            }

            showSessionCountdownNotification(context, appLabel, sessionExpirationTime)

            sessionHandler.removeCallbacksAndMessages(null)
            sessionHandler.postDelayed({
                if (temporarilyAllowedPackage != null) {
                    val expiredPackage = temporarilyAllowedPackage
                    temporarilyAllowedPackage = null
                    sessionExpirationTime = 0L
                    hasEnteredAllowedApp = false
                    dismissSessionNotification(context)
                    
                    val launchIntent = Intent(context, MainActivity::class.java).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                        putExtra("blocked_package", expiredPackage)
                    }
                    context.startActivity(launchIntent)
                }
            }, durationMs)
        }

        fun showSessionCountdownNotification(context: Context, appName: String, expirationTime: Long) {
            try {
                val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    val channel = NotificationChannel(
                        NOTIFICATION_CHANNEL_ID,
                        "App Session Timer",
                        NotificationManager.IMPORTANCE_DEFAULT
                    ).apply {
                        description = "Displays the remaining time for the current app session"
                        setShowBadge(true)
                        setSound(null, null)
                        enableVibration(false)
                    }
                    notificationManager.createNotificationChannel(channel)
                }

                val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    Notification.Builder(context, NOTIFICATION_CHANNEL_ID)
                } else {
                    @Suppress("DEPRECATION")
                    Notification.Builder(context)
                }

                val smallIconRes = context.applicationInfo.icon.takeIf { it != 0 } ?: android.R.drawable.ic_lock_idle_alarm

                builder.apply {
                    setContentTitle("Detox: $appName")
                    setContentText("Session countdown active")
                    setSmallIcon(smallIconRes)
                    setOngoing(true)
                    setOnlyAlertOnce(true)
                    setWhen(expirationTime)
                    setUsesChronometer(true)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        setChronometerCountDown(true)
                    }
                }

                notificationManager.notify(NOTIFICATION_ID, builder.build())
            } catch (e: Exception) {
                Log.e("AppBlockerService", "Error showing countdown notification", e)
            }
        }

        fun dismissSessionNotification(context: Context) {
            try {
                val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.cancel(NOTIFICATION_ID)
            } catch (e: Exception) {
                Log.e("AppBlockerService", "Error dismissing countdown notification", e)
            }
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        try {
            if (event == null) return
            
            if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
                val packageName = event.packageName?.toString() ?: return
                
                // Ignore our own app, system UI, and keyboards
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
                
                // Read blocked apps from SharedPreferences
                val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
                
                val zenModeEndTime = prefs.getLong("flutter.zen_mode_end_time", 0L)
                val isZenModeActive = System.currentTimeMillis() < zenModeEndTime

                var isZenBlock = false
                var targetBlockedPackage: String? = null
                
                if (isZenModeActive) {
                    val zenWhitelistString = prefs.getString("flutter.zen_whitelisted_apps_string", "")
                    val zenWhitelist = zenWhitelistString?.split(",")?.filter { it.isNotBlank() }?.toSet() ?: emptySet()
                    
                    val isLauncher = launcherPackages?.contains(packageName) == true || run {
                        val intent = Intent(Intent.ACTION_MAIN).apply { addCategory(Intent.CATEGORY_HOME) }
                        val resolveInfoList = packageManager.queryIntentActivities(intent, android.content.pm.PackageManager.MATCH_DEFAULT_ONLY)
                        val launchers = resolveInfoList.map { it.activityInfo.packageName }
                        launcherPackages = launchers
                        launchers.contains(packageName)
                    }

                    val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
                    if (launchIntent != null && !isLauncher && !zenWhitelist.contains(packageName) && packageName != this.packageName) {
                        targetBlockedPackage = packageName
                        isZenBlock = true
                    } else if (packageManager.getLaunchIntentForPackage(rootPackage) != null && !isLauncher && !zenWhitelist.contains(rootPackage) && rootPackage != this.packageName) {
                        targetBlockedPackage = rootPackage
                        isZenBlock = true
                    }
                } else {
                    val blockedAppsString = prefs.getString("flutter.blocked_apps_string", "")
                    val blockedApps = blockedAppsString?.split(",")?.filter { it.isNotBlank() }?.toSet() ?: emptySet()
                    
                    targetBlockedPackage = when {
                        blockedApps.contains(packageName) -> packageName
                        blockedApps.contains(rootPackage) -> rootPackage
                        else -> null
                    }
                }

                // If this is the currently allowed app session
                if (targetBlockedPackage == temporarilyAllowedPackage) {
                    hasEnteredAllowedApp = true

                    // Check if time expired
                    if (sessionExpirationTime != 0L && System.currentTimeMillis() >= sessionExpirationTime) {
                        temporarilyAllowedPackage = null
                        sessionExpirationTime = 0L
                        hasEnteredAllowedApp = false
                        sessionHandler.removeCallbacksAndMessages(null)
                        dismissSessionNotification(this)
                    } else {
                        // Active in-app session, do not block
                        return
                    }
                }

                // If user navigates away from the allowed app AFTER having entered it
                if (temporarilyAllowedPackage != null && hasEnteredAllowedApp) {
                    val isLauncher = launcherPackages?.contains(packageName) == true || run {
                        val intent = Intent(Intent.ACTION_MAIN).apply { addCategory(Intent.CATEGORY_HOME) }
                        val resolveInfoList = packageManager.queryIntentActivities(intent, android.content.pm.PackageManager.MATCH_DEFAULT_ONLY)
                        val launchers = resolveInfoList.map { it.activityInfo.packageName }
                        launcherPackages = launchers
                        launchers.contains(packageName)
                    }

                    val isOtherApp = packageManager.getLaunchIntentForPackage(packageName) != null && packageName != this.packageName

                    if (isLauncher || isOtherApp) {
                        temporarilyAllowedPackage = null
                        sessionExpirationTime = 0L
                        hasEnteredAllowedApp = false
                        sessionHandler.removeCallbacksAndMessages(null)
                        dismissSessionNotification(this)
                    }
                }

                // If not a blocked app, nothing to block
                if (targetBlockedPackage == null) {
                    return
                }

                // Target app is blocked and not in an active allowed session -> trigger blocker
                Log.d(TAG, "Blocking app: $targetBlockedPackage")
                
                dismissSessionNotification(this)
                val currentCount = prefs.getInt("flutter.cancel_count", 0)
                prefs.edit().putInt("flutter.cancel_count", currentCount + 1).apply()

                val launchIntent = Intent(this, MainActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    putExtra("blocked_package", targetBlockedPackage)
                    putExtra("is_zen_block", isZenBlock)
                }
                startActivity(launchIntent)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error in AccessibilityService", e)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        dismissSessionNotification(this)
    }

    override fun onInterrupt() {
        dismissSessionNotification(this)
    }
}
