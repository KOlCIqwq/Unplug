import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DndService {
  static const String _dndPrefKey = 'zen_dnd_silence_enabled';
  static const MethodChannel _channel = MethodChannel('com.example.detox_app/intervention');

  static final ValueNotifier<bool> isSilenceEnabledNotifier = ValueNotifier<bool>(false);

  /// Load preference from storage
  static Future<bool> loadPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_dndPrefKey) ?? false;
    isSilenceEnabledNotifier.value = enabled;
    return enabled;
  }

  /// Toggle silence preference
  static Future<void> setSilenceEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dndPrefKey, enabled);
    isSilenceEnabledNotifier.value = enabled;
  }

  /// Check whether Android Do Not Disturb permission has been granted by user
  static Future<bool> isDndPermissionGranted() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      final granted = await _channel.invokeMethod<bool>('isDndPermissionGranted');
      return granted ?? false;
    } catch (e) {
      debugPrint('[DndService] isDndPermissionGranted failed: $e');
      return false;
    }
  }

  /// Open system settings page for Do Not Disturb / Notification Policy access
  static Future<void> openDndSettings() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('openDndSettings');
    } catch (e) {
      debugPrint('[DndService] openDndSettings failed: $e');
    }
  }

  /// Enable silence / DND mode when entering Zen Space
  static Future<void> enableZenSilence() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final enabled = await loadPreference();
      if (!enabled) return;

      final hasPermission = await isDndPermissionGranted();
      if (!hasPermission) return;

      await _channel.invokeMethod('enableZenSilence');
    } catch (e) {
      debugPrint('[DndService] enableZenSilence failed: $e');
    }
  }

  /// Disable silence / restore sound when exiting Zen Space
  static Future<void> disableZenSilence() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('disableZenSilence');
    } catch (e) {
      debugPrint('[DndService] disableZenSilence failed: $e');
    }
  }
}
