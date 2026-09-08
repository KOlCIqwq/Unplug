import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/focus_task.dart';

class FocusTaskService {
  static const String _tasksKey = 'focus_tasks_json_list';
  static const String _activeTaskIdKey = 'zen_active_task_id';
  static const String _activeTaskTitleKey = 'zen_active_task_title';
  static const String _sessionStartKey = 'zen_task_session_start_ms';
  static const String _sessionDurationKey = 'zen_task_session_duration_mins';
  static const String _unassignedMinutesKey = 'unassigned_zen_minutes';

  static final ValueNotifier<List<FocusTask>> tasksNotifier = ValueNotifier<List<FocusTask>>([]);
  static final ValueNotifier<FocusTask?> activeTaskNotifier = ValueNotifier<FocusTask?>(null);
  static final ValueNotifier<int> unassignedMinutesNotifier = ValueNotifier<int>(0);

  /// Load tasks and active task from storage
  static Future<List<FocusTask>> loadTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final unassigned = prefs.getInt(_unassignedMinutesKey) ?? 0;
    unassignedMinutesNotifier.value = unassigned;

    final jsonList = prefs.getStringList(_tasksKey) ?? [];
    final List<FocusTask> loaded = [];

    for (final str in jsonList) {
      try {
        final Map<String, dynamic> map = jsonDecode(str) as Map<String, dynamic>;
        loaded.add(FocusTask.fromJson(map));
      } catch (e) {
        debugPrint('[FocusTaskService] Failed to parse task: $e');
      }
    }

    // Sort: uncompleted first by creation date descending, then completed
    loaded.sort((a, b) {
      if (a.isCompleted != b.isCompleted) {
        return a.isCompleted ? 1 : -1;
      }
      return b.createdAt.compareTo(a.createdAt);
    });

    tasksNotifier.value = loaded;

    // Check active task
    final activeId = prefs.getString(_activeTaskIdKey);
    if (activeId != null && activeId.isNotEmpty) {
      final task = loaded.where((t) => t.id == activeId).firstOrNull;
      activeTaskNotifier.value = task;
    } else {
      activeTaskNotifier.value = null;
    }

    return loaded;
  }

  static Future<void> _saveTasks(List<FocusTask> tasks) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = tasks.map((t) => jsonEncode(t.toJson())).toList();
    await prefs.setStringList(_tasksKey, jsonList);
    tasksNotifier.value = List.from(tasks);
  }

  /// Create a new focus task with target estimated minutes
  static Future<FocusTask> createTask(String title, int estimatedMinutes) async {
    final id = 'task_${DateTime.now().millisecondsSinceEpoch}';
    final newTask = FocusTask(
      id: id,
      title: title.trim().isEmpty ? 'Focus Session' : title.trim(),
      estimatedMinutes: estimatedMinutes > 0 ? estimatedMinutes : 25,
      spentMinutes: 0,
      isCompleted: false,
    );

    final current = List<FocusTask>.from(tasksNotifier.value);
    current.insert(0, newTask);
    await _saveTasks(current);
    return newTask;
  }

  /// Update an existing task
  static Future<void> updateTask(FocusTask updated) async {
    final current = List<FocusTask>.from(tasksNotifier.value);
    final index = current.indexWhere((t) => t.id == updated.id);
    if (index != -1) {
      current[index] = updated;
      await _saveTasks(current);
      if (activeTaskNotifier.value?.id == updated.id) {
        activeTaskNotifier.value = updated;
      }
    }
  }

  /// Delete a task by ID
  static Future<void> deleteTask(String id) async {
    final current = List<FocusTask>.from(tasksNotifier.value);
    current.removeWhere((t) => t.id == id);
    await _saveTasks(current);

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_activeTaskIdKey) == id) {
      await clearActiveZenSession();
    }
  }

  /// Toggle completed state
  static Future<void> toggleTaskComplete(String id) async {
    final current = List<FocusTask>.from(tasksNotifier.value);
    final index = current.indexWhere((t) => t.id == id);
    if (index != -1) {
      final task = current[index];
      final newCompleted = !task.isCompleted;
      current[index] = task.copyWith(
        isCompleted: newCompleted,
        spentMinutes: newCompleted && task.spentMinutes < task.estimatedMinutes
            ? task.estimatedMinutes
            : task.spentMinutes,
      );
      await _saveTasks(current);
      if (activeTaskNotifier.value?.id == id) {
        activeTaskNotifier.value = current[index];
      }
    }
  }

  /// Start a Zen session concentrating on a chosen task
  static Future<void> startZenForTask(String taskId, int durationMinutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeTaskIdKey, taskId);
    await prefs.setInt(_sessionStartKey, DateTime.now().millisecondsSinceEpoch);
    await prefs.setInt(_sessionDurationKey, durationMinutes);

    final task = tasksNotifier.value.where((t) => t.id == taskId).firstOrNull;
    if (task != null) {
      await prefs.setString(_activeTaskTitleKey, task.title);
    }
    activeTaskNotifier.value = task;
  }

  /// Complete or exit current Zen session, recording time spent towards the chosen task
  static Future<Map<String, dynamic>?> finishZenSession({bool markTaskDone = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final activeId = prefs.getString(_activeTaskIdKey);
    final startMs = prefs.getInt(_sessionStartKey) ?? 0;
    final durationMins = prefs.getInt(_sessionDurationKey) ?? 0;

    if (activeId == null || activeId.isEmpty || startMs == 0) {
      await clearActiveZenSession();
      return null;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final elapsedMs = now - startMs;
    // Round to nearest minute, at least 1 minute if session lasted >= 30 seconds
    int elapsedMins = (elapsedMs / (60 * 1000)).round();
    if (elapsedMins <= 0 && elapsedMs >= 30 * 1000) {
      elapsedMins = 1;
    }
    if (durationMins > 0 && elapsedMins > durationMins) {
      elapsedMins = durationMins;
    }

    final current = List<FocusTask>.from(tasksNotifier.value);
    final index = current.indexWhere((t) => t.id == activeId);
    FocusTask? updatedTask;
    bool wasFulfilled = false;

    if (index != -1) {
      final task = current[index];
      final newSpent = task.spentMinutes + elapsedMins;
      final bool nowCompleted = markTaskDone || newSpent >= task.estimatedMinutes;
      wasFulfilled = nowCompleted && !task.isCompleted;

      updatedTask = task.copyWith(
        spentMinutes: newSpent,
        isCompleted: nowCompleted || task.isCompleted,
      );
      current[index] = updatedTask;
      await _saveTasks(current);
    }

    await clearActiveZenSession();

    return {
      'task': updatedTask,
      'minutesAdded': elapsedMins,
      'wasFulfilled': wasFulfilled,
    };
  }

  /// Clears active task session tracking
  static Future<void> clearActiveZenSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activeTaskIdKey);
    await prefs.remove(_activeTaskTitleKey);
    await prefs.remove(_sessionStartKey);
    await prefs.remove(_sessionDurationKey);
    activeTaskNotifier.value = null;
  }

  /// Retrieve unassigned focus minutes
  static Future<int> getUnassignedMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    final mins = prefs.getInt(_unassignedMinutesKey) ?? 0;
    unassignedMinutesNotifier.value = mins;
    return mins;
  }

  /// Record unassigned focus minutes (e.g. from Widget session)
  static Future<void> addUnassignedMinutes(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_unassignedMinutesKey) ?? 0;
    final updated = current + minutes;
    await prefs.setInt(_unassignedMinutesKey, updated);
    unassignedMinutesNotifier.value = updated;
  }

  /// Assign accumulated unassigned minutes to a selected task
  static Future<bool> assignUnassignedMinutesToTask(String taskId) async {
    final prefs = await SharedPreferences.getInstance();
    final unassigned = prefs.getInt(_unassignedMinutesKey) ?? 0;
    if (unassigned <= 0) return false;

    final current = List<FocusTask>.from(tasksNotifier.value);
    final index = current.indexWhere((t) => t.id == taskId);
    bool wasFulfilled = false;

    if (index != -1) {
      final task = current[index];
      final newSpent = task.spentMinutes + unassigned;
      final bool nowCompleted = newSpent >= task.estimatedMinutes;
      wasFulfilled = nowCompleted && !task.isCompleted;

      current[index] = task.copyWith(
        spentMinutes: newSpent,
        isCompleted: nowCompleted || task.isCompleted,
      );
      await _saveTasks(current);
    }

    await prefs.setInt(_unassignedMinutesKey, 0);
    unassignedMinutesNotifier.value = 0;
    return wasFulfilled;
  }

  /// Clear or dismiss unassigned minutes
  static Future<void> clearUnassignedMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_unassignedMinutesKey, 0);
    unassignedMinutesNotifier.value = 0;
  }
}
