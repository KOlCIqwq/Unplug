package com.example.detox_app

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.os.Build
import android.provider.Settings
import android.util.Log

object ZenDndManager {
    private const val TAG = "ZenDndManager"
    private const val PREFS_NAME = "FlutterSharedPreferences"
    private const val KEY_DND_ENABLED = "flutter.zen_dnd_silence_enabled"
    private const val KEY_PREV_INTERRUPTION_FILTER = "flutter.zen_prev_interruption_filter"
    private const val KEY_PREV_RINGER_MODE = "flutter.zen_prev_ringer_mode"
    private const val KEY_IS_DND_ACTIVE = "flutter.zen_is_dnd_active"

    fun isDndPermissionGranted(context: Context): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            nm?.isNotificationPolicyAccessGranted == true
        } else {
            true
        }
    }

    fun openDndSettings(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val intent = Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            context.startActivity(intent)
        }
    }

    fun isSilenceEnabled(context: Context): Boolean {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getBoolean(KEY_DND_ENABLED, false)
    }

    fun enableZenSilence(context: Context) {
        try {
            if (!isSilenceEnabled(context)) return
            if (!isDndPermissionGranted(context)) {
                Log.w(TAG, "Cannot enable Zen silence: DND permission not granted")
                return
            }

            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            val am = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager

            // Save previous states
            val prevFilter = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                nm?.currentInterruptionFilter ?: NotificationManager.INTERRUPTION_FILTER_ALL
            } else {
                NotificationManager.INTERRUPTION_FILTER_ALL
            }
            val prevRinger = am?.ringerMode ?: AudioManager.RINGER_MODE_NORMAL

            prefs.edit()
                .putInt(KEY_PREV_INTERRUPTION_FILTER, prevFilter)
                .putInt(KEY_PREV_RINGER_MODE, prevRinger)
                .putBoolean(KEY_IS_DND_ACTIVE, true)
                .apply()

            // Set DND to Alarms only (so user-configured alarms still ring)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                nm?.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_ALARMS)
            }
            am?.ringerMode = AudioManager.RINGER_MODE_SILENT
            Log.d(TAG, "Zen silence enabled: DND set to ALARMS, ringer set to SILENT")
        } catch (e: Exception) {
            Log.e(TAG, "Error enabling Zen silence", e)
        }
    }

    fun disableZenSilence(context: Context) {
        try {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val isDndActive = prefs.getBoolean(KEY_IS_DND_ACTIVE, false)
            if (!isDndActive) return

            if (isDndPermissionGranted(context)) {
                val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                val am = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager

                val prevFilter = prefs.getInt(KEY_PREV_INTERRUPTION_FILTER, NotificationManager.INTERRUPTION_FILTER_ALL)
                val prevRinger = prefs.getInt(KEY_PREV_RINGER_MODE, AudioManager.RINGER_MODE_NORMAL)

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    nm?.setInterruptionFilter(prevFilter)
                }
                am?.ringerMode = prevRinger
                Log.d(TAG, "Zen silence disabled: restored filter $prevFilter and ringer $prevRinger")
            }

            prefs.edit()
                .putBoolean(KEY_IS_DND_ACTIVE, false)
                .remove(KEY_PREV_INTERRUPTION_FILTER)
                .remove(KEY_PREV_RINGER_MODE)
                .apply()
        } catch (e: Exception) {
            Log.e(TAG, "Error disabling Zen silence", e)
        }
    }
}
