import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../models/alarm_item.dart';
import '../screens/alarm_ringing_screen.dart';

class AlarmService {
  static const String _alarmsKey = 'alarms_json_list';
  static const MethodChannel _channel = MethodChannel('com.example.detox_app/intervention');

  static final ValueNotifier<List<AlarmItem>> alarmsNotifier = ValueNotifier<List<AlarmItem>>([]);
  static final ValueNotifier<AlarmItem?> ringingAlarmNotifier = ValueNotifier<AlarmItem?>(null);

  static Timer? _checkTimer;
  static bool _isRingingScreenShowing = false;

  /// Initialize service, load alarms, schedule foreground loop and check pending alarm
  static Future<void> initialize() async {
    await loadAlarms();
    _startPeriodicChecker();
    _checkPendingNativeAlarm();
  }

  static void _startPeriodicChecker() {
    _checkTimer?.cancel();
    // Check every 5 seconds
    _checkTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      checkUpcomingAlarms();
    });
  }

  /// Load all alarms from SharedPreferences
  static Future<List<AlarmItem>> loadAlarms() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_alarmsKey) ?? [];
    final List<AlarmItem> loaded = [];

    for (final str in jsonList) {
      try {
        final Map<String, dynamic> map = jsonDecode(str) as Map<String, dynamic>;
        loaded.add(AlarmItem.fromJson(map));
      } catch (e) {
        debugPrint('[AlarmService] Error decoding alarm: $e');
      }
    }

    // Sort by next trigger time
    loaded.sort((a, b) => a.nextTriggerDateTime.compareTo(b.nextTriggerDateTime));
    alarmsNotifier.value = loaded;
    return loaded;
  }

  static Future<void> _saveAlarms(List<AlarmItem> alarms) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = alarms.map((a) => jsonEncode(a.toJson())).toList();
    await prefs.setStringList(_alarmsKey, jsonList);
    alarms.sort((a, b) => a.nextTriggerDateTime.compareTo(b.nextTriggerDateTime));
    alarmsNotifier.value = List.from(alarms);
    _syncNativeAlarms(alarms);
  }

  /// Sync all enabled alarms with native AlarmManager
  static Future<void> _syncNativeAlarms(List<AlarmItem> alarms) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      for (final alarm in alarms) {
        if (alarm.isEnabled) {
          final nextTrigger = alarm.nextTriggerDateTime;
          await _channel.invokeMethod('scheduleAlarm', {
            'id': alarm.id,
            'timestamp': nextTrigger.millisecondsSinceEpoch,
            'title': alarm.title,
          });
        } else {
          await _channel.invokeMethod('cancelAlarm', {
            'id': alarm.id,
          });
        }
      }
    } catch (e) {
      debugPrint('[AlarmService] Native alarm sync failed: $e');
    }
  }

  /// Add a new alarm
  static Future<AlarmItem> addAlarm({
    required String title,
    required int hour,
    required int minute,
    List<int>? daysOfWeek,
    bool vibrate = true,
    bool sound = true,
  }) async {
    final newAlarm = AlarmItem(
      id: 'alarm_${DateTime.now().millisecondsSinceEpoch}',
      title: title.trim().isEmpty ? 'Alarm' : title.trim(),
      hour: hour,
      minute: minute,
      daysOfWeek: daysOfWeek ?? [],
      vibrate: vibrate,
      sound: sound,
      isEnabled: true,
    );

    final current = List<AlarmItem>.from(alarmsNotifier.value);
    current.add(newAlarm);
    await _saveAlarms(current);
    return newAlarm;
  }

  /// Update existing alarm
  static Future<void> updateAlarm(AlarmItem alarm) async {
    final current = List<AlarmItem>.from(alarmsNotifier.value);
    final index = current.indexWhere((a) => a.id == alarm.id);
    if (index != -1) {
      current[index] = alarm;
      await _saveAlarms(current);
    }
  }

  /// Toggle alarm on or off
  static Future<void> toggleAlarm(String id, bool enabled) async {
    final current = List<AlarmItem>.from(alarmsNotifier.value);
    final index = current.indexWhere((a) => a.id == id);
    if (index != -1) {
      current[index] = current[index].copyWith(isEnabled: enabled);
      await _saveAlarms(current);
    }
  }

  /// Delete alarm
  static Future<void> deleteAlarm(String id) async {
    final current = List<AlarmItem>.from(alarmsNotifier.value);
    current.removeWhere((a) => a.id == id);
    await _saveAlarms(current);
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _channel.invokeMethod('cancelAlarm', {'id': id});
      } catch (_) {}
    }
  }

  /// Check upcoming alarms (runs periodically and on app resume)
  static void checkUpcomingAlarms() {
    if (_isRingingScreenShowing) return;
    final now = DateTime.now();

    for (final alarm in alarmsNotifier.value) {
      if (!alarm.isEnabled) continue;

      // Check if this alarm matches the current minute
      final isSameTime = alarm.hour == now.hour && alarm.minute == now.minute;
      final isDayMatching = alarm.daysOfWeek.isEmpty || alarm.daysOfWeek.contains(now.weekday);

      if (isSameTime && isDayMatching) {
        // Prevent duplicate trigger in the same minute
        if (alarm.lastTriggered != null &&
            alarm.lastTriggered!.year == now.year &&
            alarm.lastTriggered!.month == now.month &&
            alarm.lastTriggered!.day == now.day &&
            alarm.lastTriggered!.hour == now.hour &&
            alarm.lastTriggered!.minute == now.minute) {
          continue;
        }

        triggerAlarm(alarm);
        break;
      }
    }
  }

  /// Trigger alarm ringing
  static Future<void> triggerAlarm(AlarmItem alarm) async {
    if (_isRingingScreenShowing) return;
    _isRingingScreenShowing = true;
    ringingAlarmNotifier.value = alarm;

    // Start native ringing sound and vibration
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _channel.invokeMethod('startAlarmRinging', {
          'id': alarm.id,
          'title': alarm.title,
        });
      } catch (e) {
        debugPrint('[AlarmService] Error starting native ringtone: $e');
      }
    }

    // Mark last triggered
    final current = List<AlarmItem>.from(alarmsNotifier.value);
    final index = current.indexWhere((a) => a.id == alarm.id);
    if (index != -1) {
      current[index] = current[index].copyWith(
        lastTriggered: DateTime.now(),
        // If it was a one-time alarm, disable it after ringing
        isEnabled: current[index].daysOfWeek.isNotEmpty,
      );
      await _saveAlarms(current);
    }

    // Show full-screen ringing UI
    void showRingingUI() {
      if (navigatorKey.currentState != null) {
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (context) => AlarmRingingScreen(alarm: alarm),
          ),
        ).then((_) {
          _isRingingScreenShowing = false;
          ringingAlarmNotifier.value = null;
        });
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          showRingingUI();
        });
      }
    }
    showRingingUI();
  }

  /// Dismiss alarm
  static Future<void> dismissAlarm(String id) async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _channel.invokeMethod('stopAlarmRinging');
      } catch (_) {}
    }
    _isRingingScreenShowing = false;
    ringingAlarmNotifier.value = null;
  }

  /// Snooze alarm for given minutes (default 5 min)
  static Future<void> snoozeAlarm(String id, {int snoozeMinutes = 5}) async {
    await dismissAlarm(id);

    final current = alarmsNotifier.value.where((a) => a.id == id).firstOrNull;
    final snoozeTime = DateTime.now().add(Duration(minutes: snoozeMinutes));

    // Create a temporary snooze alarm
    final snoozeAlarmItem = AlarmItem(
      id: 'snooze_${DateTime.now().millisecondsSinceEpoch}',
      title: current != null ? 'Snooze: ${current.title}' : 'Snoozed Alarm',
      hour: snoozeTime.hour,
      minute: snoozeTime.minute,
      daysOfWeek: [],
      isEnabled: true,
    );

    final list = List<AlarmItem>.from(alarmsNotifier.value)..add(snoozeAlarmItem);
    await _saveAlarms(list);
  }

  /// Check if app was launched/resumed with pending alarm from background
  static Future<void> _checkPendingNativeAlarm() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final res = await _channel.invokeMethod('getPendingAlarm');
      if (res != null && res is Map && res['alarmId'] != null) {
        final alarmId = res['alarmId'] as String;
        final title = res['title'] as String? ?? 'Alarm';
        final existing = alarmsNotifier.value.where((a) => a.id == alarmId).firstOrNull;
        final alarmToRing = existing ??
            AlarmItem(
              id: alarmId,
              title: title,
              hour: DateTime.now().hour,
              minute: DateTime.now().minute,
            );
        triggerAlarm(alarmToRing);
      }
    } catch (e) {
      debugPrint('[AlarmService] Error getting pending native alarm: $e');
    }
  }

  /// Test alarm helper: triggers immediately
  static void testAlarmNow({String title = 'Test Alarm'}) {
    final now = DateTime.now();
    final testAlarm = AlarmItem(
      id: 'test_alarm_${now.millisecondsSinceEpoch}',
      title: title,
      hour: now.hour,
      minute: now.minute,
      daysOfWeek: [],
    );
    triggerAlarm(testAlarm);
  }
}
