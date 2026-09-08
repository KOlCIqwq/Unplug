import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unplug/models/focus_task.dart';
import 'package:unplug/services/focus_task_service.dart';
import 'package:unplug/models/alarm_item.dart';
import 'package:unplug/services/alarm_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('FocusTask Model Tests', () {
    test('FocusTask initial calculation and properties', () {
      final task = FocusTask(
        id: 't1',
        title: 'Study Physics',
        estimatedMinutes: 60,
        spentMinutes: 15,
      );

      expect(task.remainingMinutes, 45);
      expect(task.progress, 0.25);
      expect(task.percentage, 25);
      expect(task.isFulfilled, false);
      expect(task.isCompleted, false);
    });

    test('FocusTask fulfillment when spent >= estimated', () {
      final task = FocusTask(
        id: 't2',
        title: 'Read Book',
        estimatedMinutes: 30,
        spentMinutes: 35,
      );

      expect(task.remainingMinutes, 0);
      expect(task.progress, 1.0);
      expect(task.percentage, 100);
      expect(task.isFulfilled, true);
    });

    test('FocusTask JSON serialization round-trip', () {
      final task = FocusTask(
        id: 't3',
        title: 'Workout',
        estimatedMinutes: 45,
        spentMinutes: 20,
        isCompleted: false,
      );

      final json = task.toJson();
      final reconstructed = FocusTask.fromJson(json);

      expect(reconstructed.id, task.id);
      expect(reconstructed.title, task.title);
      expect(reconstructed.estimatedMinutes, task.estimatedMinutes);
      expect(reconstructed.spentMinutes, task.spentMinutes);
      expect(reconstructed.isCompleted, task.isCompleted);
    });
  });

  group('FocusTaskService Tests', () {
    test('Create, retrieve, and delete task', () async {
      final created = await FocusTaskService.createTask('Write code', 45);
      expect(created.title, 'Write code');
      expect(created.estimatedMinutes, 45);

      final tasks = await FocusTaskService.loadTasks();
      expect(tasks.any((t) => t.id == created.id), true);

      await FocusTaskService.deleteTask(created.id);
      final tasksAfterDelete = await FocusTaskService.loadTasks();
      expect(tasksAfterDelete.any((t) => t.id == created.id), false);
    });

    test('Start Zen session for task and fulfill upon completion', () async {
      final task = await FocusTaskService.createTask('Deep Study', 30);
      await FocusTaskService.startZenForTask(task.id, 30);

      expect(FocusTaskService.activeTaskNotifier.value?.id, task.id);

      // Finish session with markTaskDone: true
      final summary = await FocusTaskService.finishZenSession(markTaskDone: true);
      expect(summary, isNotNull);
      expect(summary!['wasFulfilled'], true);

      final updated = FocusTaskService.tasksNotifier.value.firstWhere((t) => t.id == task.id);
      expect(updated.isCompleted, true);
    });

    test('Unassigned minutes policy and task assignment', () async {
      final task = await FocusTaskService.createTask('Writing Documentation', 60);
      expect(task.spentMinutes, 0);

      // Simulate 20 minutes of unassigned Zen time from widget
      await FocusTaskService.addUnassignedMinutes(20);
      expect(FocusTaskService.unassignedMinutesNotifier.value, 20);

      // Assign to the task
      final wasFulfilled = await FocusTaskService.assignUnassignedMinutesToTask(task.id);
      expect(wasFulfilled, false);
      expect(FocusTaskService.unassignedMinutesNotifier.value, 0);

      final updated = FocusTaskService.tasksNotifier.value.firstWhere((t) => t.id == task.id);
      expect(updated.spentMinutes, 20);
      expect(updated.remainingMinutes, 40);
    });
  });

  group('AlarmItem Model Tests', () {
    test('AlarmItem formatting and repeat summary', () {
      final alarm = AlarmItem(
        id: 'a1',
        title: 'Morning Meeting',
        hour: 9,
        minute: 5,
        daysOfWeek: [1, 2, 3, 4, 5],
      );

      expect(alarm.formattedTime, '09:05');
      expect(alarm.formattedTimeAmPm, '9:05 AM');
      expect(alarm.repeatSummary, 'Weekdays');
      expect(alarm.isEnabled, true);
    });

    test('AlarmItem one-time next trigger calculation', () {
      final now = DateTime.now();
      final inTenMinutes = now.add(const Duration(minutes: 10));

      final alarm = AlarmItem(
        id: 'a2',
        title: 'Break',
        hour: inTenMinutes.hour,
        minute: inTenMinutes.minute,
        daysOfWeek: [],
      );

      final next = alarm.nextTriggerDateTime;
      expect(next.hour, inTenMinutes.hour);
      expect(next.minute, inTenMinutes.minute);
      expect(next.isAfter(now), true);
    });

    test('AlarmItem JSON serialization', () {
      final alarm = AlarmItem(
        id: 'a3',
        title: 'Workout Alarm',
        hour: 18,
        minute: 30,
        daysOfWeek: [1, 3, 5],
        vibrate: true,
        sound: true,
      );

      final json = alarm.toJson();
      final parsed = AlarmItem.fromJson(json);

      expect(parsed.id, alarm.id);
      expect(parsed.title, alarm.title);
      expect(parsed.hour, 18);
      expect(parsed.minute, 30);
      expect(parsed.daysOfWeek, [1, 3, 5]);
    });
  });

  group('AlarmService Tests', () {
    test('Add, toggle, snooze, and delete alarm', () async {
      final alarm = await AlarmService.addAlarm(
        title: 'Test Reminder',
        hour: 14,
        minute: 0,
        daysOfWeek: [],
      );

      expect(AlarmService.alarmsNotifier.value.any((a) => a.id == alarm.id), true);

      // Toggle
      await AlarmService.toggleAlarm(alarm.id, false);
      expect(AlarmService.alarmsNotifier.value.firstWhere((a) => a.id == alarm.id).isEnabled, false);

      // Snooze
      await AlarmService.snoozeAlarm(alarm.id, snoozeMinutes: 5);
      expect(AlarmService.alarmsNotifier.value.any((a) => a.title.contains('Snooze')), true);

      // Delete
      await AlarmService.deleteAlarm(alarm.id);
      expect(AlarmService.alarmsNotifier.value.any((a) => a.id == alarm.id), false);
    });
  });
}
