import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:async';
import '../models/focus_task.dart';
import '../services/focus_task_service.dart';
import '../services/alarm_service.dart';
import '../services/dnd_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  int _cancelCount = 0;
  int _totalSavedMinutes = 0;
  bool _isLoading = true;
  int _zenModeEndTime = 0;
  int _selectedZenMinutes = 15;
  Timer? _zenTimer;

  List<Map<String, dynamic>> _appUsageList = [];
  Map<String, AppInfo> _installedAppMap = {};
  int _totalUsedMinutes = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FocusTaskService.loadTasks();
    FocusTaskService.getUnassignedMinutes();
    AlarmService.loadAlarms();
    _loadAllData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPendingAssignTask();
    });
  }

  @override
  void dispose() {
    _zenTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadStats();
      FocusTaskService.loadTasks();
      FocusTaskService.getUnassignedMinutes();
      _checkPendingAssignTask();
    }
  }

  String _getTodayDateKey() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }

  Future<void> _loadAllData() async {
    await _loadInstalledApps();
    await _loadStats();
  }

  Future<void> _loadInstalledApps() async {
    try {
      if (!kIsWeb && Platform.isAndroid) {
        final apps = await InstalledApps.getInstalledApps(
          excludeSystemApps: true,
          withIcon: true,
        );
        final Map<String, AppInfo> map = {};
        for (final app in apps) {
          map[app.packageName] = app;
        }
        if (mounted) {
          setState(() {
            _installedAppMap = map;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _loadStats() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      await prefs.reload();
    } catch (_) {}
    final dateKey = _getTodayDateKey();
    final blocked = prefs.getStringList('blocked_apps') ?? [];

    final List<Map<String, dynamic>> usageList = [];
    int totalMins = 0;
    int calculatedSavedMinutes = prefs.getInt('total_saved_minutes') ?? 0;
    final int cancelCount = prefs.getInt('cancel_count') ?? 0;

    for (final pkg in blocked) {
      final limitMins = prefs.getInt('limit_$pkg') ?? 0;
      final usedMs = prefs.getInt('usage_${dateKey}_$pkg') ?? 0;
      final usedMins = (usedMs / (60 * 1000)).toInt();
      totalMins += usedMins;

      final totalSessionMs = prefs.getInt('total_session_ms_$pkg') ?? 0;
      final sessionCount = prefs.getInt('sessions_count_$pkg') ?? 0;
      final int avgSessionMins = (sessionCount > 0 && totalSessionMs > 0)
          ? ((totalSessionMs / sessionCount) / (60 * 1000)).round().clamp(
              1,
              120,
            )
          : 8;

      final int appResists = prefs.getInt('resists_$pkg') ?? 0;
      final int appSavedMins =
          prefs.getInt('saved_minutes_$pkg') ?? (appResists * avgSessionMins);

      usageList.add({
        'package': pkg,
        'limit': limitMins,
        'used': usedMins,
        'avgSession': avgSessionMins,
        'sessionCount': sessionCount,
        'resists': appResists,
        'savedMinutes': appSavedMins,
      });
    }

    // Fallback if total_saved_minutes was not tracked in older runs
    if (calculatedSavedMinutes == 0 && cancelCount > 0) {
      calculatedSavedMinutes = cancelCount * 8;
    }

    // Sort by most used first, then by resists
    usageList.sort((a, b) {
      final int usedComp = (b['used'] as int).compareTo(a['used'] as int);
      if (usedComp != 0) return usedComp;
      return (b['resists'] as int).compareTo(a['resists'] as int);
    });

    if (mounted) {
      setState(() {
        _cancelCount = cancelCount;
        _totalSavedMinutes = calculatedSavedMinutes;
        _zenModeEndTime = prefs.getInt('zen_mode_end_time') ?? 0;
        _appUsageList = usageList;
        _totalUsedMinutes = totalMins;
        _isLoading = false;
      });
    }

    _zenTimer?.cancel();
    _zenTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_zenModeEndTime > 0 &&
          DateTime.now().millisecondsSinceEpoch > _zenModeEndTime) {
        _onZenTimerFinished();
        if (mounted) {
          setState(() {
            _zenModeEndTime = 0;
          });
        }
      } else if (_zenModeEndTime > 0) {
        if (mounted) {
          setState(() {});
        }
      }
    });
  }

  Future<void> _onZenTimerFinished() async {
    await DndService.disableZenSilence();
    final summary = await FocusTaskService.finishZenSession();
    if (mounted && summary != null) {
      _showZenCompletionDialog(summary);
    }
  }

  Future<void> _enterZenSpace(int minutes) async {
    await _promptStartZenSpace(defaultMinutes: minutes);
  }

  Future<void> _exitZenSpace() async {
    await DndService.disableZenSilence();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('zen_mode_end_time', 0);
    final summary = await FocusTaskService.finishZenSession();
    if (mounted) {
      setState(() {
        _zenModeEndTime = 0;
      });
      if (summary != null && (summary['minutesAdded'] as int) > 0) {
        final task = summary['task'] as FocusTask?;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Focused for ${summary['minutesAdded']}m on "${task?.title ?? 'Task'}".',
            ),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      }
    }
    _notifyWidgetUpdate();
  }

  Future<void> _completeTaskEarly() async {
    await DndService.disableZenSilence();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('zen_mode_end_time', 0);
    final summary = await FocusTaskService.finishZenSession(markTaskDone: true);
    if (mounted) {
      setState(() {
        _zenModeEndTime = 0;
      });
      if (summary != null) {
        _showZenCompletionDialog(summary);
      }
    }
    _notifyWidgetUpdate();
  }

  Future<void> _promptStartZenSpace({FocusTask? preselectedTask, int? defaultMinutes}) async {
    final tasks = FocusTaskService.tasksNotifier.value;
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _SelectTaskForZenSheet(
        tasks: tasks,
        preselectedTask: preselectedTask,
        initialMinutes: defaultMinutes ?? _selectedZenMinutes,
      ),
    );

    if (result != null) {
      final FocusTask chosenTask = result['task'] as FocusTask;
      final int minutes = result['minutes'] as int;
      final bool setAlarm = result['setAlarm'] as bool? ?? true;
      final bool silencePhone = result['silencePhone'] as bool? ?? false;

      await FocusTaskService.startZenForTask(chosenTask.id, minutes);
      if (silencePhone) {
        await DndService.setSilenceEnabled(true);
        await DndService.enableZenSilence();
      }

      final prefs = await SharedPreferences.getInstance();
      final endTime = DateTime.now().millisecondsSinceEpoch + (minutes * 60 * 1000);
      await prefs.setInt('zen_mode_end_time', endTime);
      await prefs.setInt('zen_last_selected_minutes', minutes);

      if (setAlarm) {
        final alarmTime = DateTime.now().add(Duration(minutes: minutes));
        await AlarmService.addAlarm(
          title: 'Zen Complete: ${chosenTask.title}',
          hour: alarmTime.hour,
          minute: alarmTime.minute,
          daysOfWeek: [],
        );
      }

      if (mounted) {
        setState(() {
          _zenModeEndTime = endTime;
          _selectedZenMinutes = minutes;
        });
      }
      _notifyWidgetUpdate();
    }
  }

  Future<void> _checkPendingAssignTask() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      const platform = MethodChannel('com.example.detox_app/intervention');
      final shouldOpen = await platform.invokeMethod<bool>('getPendingAssignTask') ?? false;
      if (shouldOpen && mounted) {
        if (_zenModeEndTime > DateTime.now().millisecondsSinceEpoch) {
          _showAssignActiveZenTaskSheet();
        } else {
          _promptStartZenSpace();
        }
      }
    } catch (_) {}
  }

  void _showAssignActiveZenTaskSheet() {
    final tasks = FocusTaskService.tasksNotifier.value;
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _SelectTaskForZenSheet(
        tasks: tasks,
        initialMinutes: _selectedZenMinutes,
        isAssigningToActiveZen: true,
      ),
    ).then((result) async {
      if (result != null && result is Map) {
        final FocusTask chosenTask = result['task'] as FocusTask;
        final int remainingMs = _zenModeEndTime - DateTime.now().millisecondsSinceEpoch;
        final int remainingMins = (remainingMs / (60 * 1000)).ceil().clamp(1, 120);
        await FocusTaskService.startZenForTask(chosenTask.id, remainingMins);
        _notifyWidgetUpdate();
        if (mounted) {
          setState(() {});
        }
      }
    });
  }

  void _openAssignUnassignedMinutesDialog(BuildContext context, int unassignedMins) {
    final colorScheme = Theme.of(context).colorScheme;
    final messenger = ScaffoldMessenger.of(context);
    final tasks = FocusTaskService.tasksNotifier.value.where((t) => !t.isCompleted).toList();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.hourglass_bottom_rounded, color: colorScheme.primary),
            const SizedBox(width: 8),
            const Text('Assign Focus Time'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Choose a task to credit +$unassignedMins minutes of Zen mode:',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              if (tasks.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  child: Text(
                    'No active tasks available. Create a new task first.',
                    style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: tasks.length,
                    itemBuilder: (c, idx) {
                      final t = tasks[idx];
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.check_circle_outline, color: colorScheme.primary),
                        title: Text(t.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('${t.spentMinutes} / ${t.estimatedMinutes}m fulfilled'),
                        trailing: Text(
                          '+${unassignedMins}m',
                          style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.bold),
                        ),
                        onTap: () async {
                          Navigator.pop(ctx);
                          final wasFulfilled = await FocusTaskService.assignUnassignedMinutesToTask(t.id);
                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text('Added ${unassignedMins}m to "${t.title}"!'),
                                backgroundColor: colorScheme.primary,
                              ),
                            );
                            if (wasFulfilled) {
                              _showZenCompletionDialog({
                                'task': t.copyWith(spentMinutes: t.spentMinutes + unassignedMins),
                                'minutesAdded': unassignedMins,
                                'wasFulfilled': true,
                              });
                            }
                          }
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _openTaskEditor(context);
            },
            child: const Text('+ New Task'),
          ),
        ],
      ),
    );
  }

  void _showZenCompletionDialog(Map<String, dynamic> summary) {
    final FocusTask? task = summary['task'] as FocusTask?;
    final int minutesAdded = summary['minutesAdded'] as int? ?? 0;
    final bool wasFulfilled = summary['wasFulfilled'] as bool? ?? false;
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              wasFulfilled ? Icons.celebration_rounded : Icons.check_circle_rounded,
              color: colorScheme.primary,
              size: 28,
            ),
            const SizedBox(width: 10),
            Text(wasFulfilled ? 'Goal Fulfilled!' : 'Session Complete!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You concentrated for $minutesAdded minutes on "${task?.title ?? 'your task'}".',
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 12),
            if (task != null) ...[
              LinearProgressIndicator(
                value: task.progress,
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
                color: colorScheme.primary,
                backgroundColor: colorScheme.outline.withValues(alpha: 0.2),
              ),
              const SizedBox(height: 8),
              Text(
                'Total: ${task.spentMinutes} / ${task.estimatedMinutes} min (${task.percentage}% fulfilled)',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Awesome'),
          ),
        ],
      ),
    );
  }

  void _openTaskEditor(BuildContext context, {FocusTask? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _TaskEditorSheet(existing: existing),
    );
  }

  Future<void> _notifyWidgetUpdate() async {
    try {
      const platform = MethodChannel('com.example.detox_app/intervention');
      await platform.invokeMethod('updateZenWidget');
    } catch (e) {
      debugPrint('[Dashboard] updateZenWidget failed: $e');
    }
  }

  String _formatTime(DateTime time) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return '${twoDigits(time.hour)}:${twoDigits(time.minute)}';
  }

  String _formatCountdown(int targetEpochMs) {
    final diffMs = targetEpochMs - DateTime.now().millisecondsSinceEpoch;
    if (diffMs <= 0) return '00:00';
    final totalSeconds = (diffMs / 1000).ceil();
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    String twoDigits(int n) => n.toString().padLeft(2, '0');

    if (hours > 0) {
      return '${twoDigits(hours)}:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  String _formatMinutes(int minutes) {
    if (minutes <= 0) return '0m';
    if (minutes >= 60) {
      final h = minutes ~/ 60;
      final m = minutes % 60;
      return m > 0 ? '${h}h ${m}m' : '${h}h';
    }
    return '${minutes}m';
  }

  String _getAppName(String packageName) {
    final app = _installedAppMap[packageName];
    if (app != null && app.name.isNotEmpty) {
      return app.name;
    }
    final parts = packageName.split('.');
    if (parts.isNotEmpty) {
      final last = parts.last;
      return last[0].toUpperCase() + last.substring(1);
    }
    return packageName;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final colorScheme = Theme.of(context).colorScheme;
    final mostUsedApp =
        _appUsageList.isNotEmpty && (_appUsageList.first['used'] as int) > 0
        ? _appUsageList.first
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/logo.png',
                width: 30,
                height: 30,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Unplug',
              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
            ),
          ],
        ),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Overview Cards (Saved Time & Tracked Usage)
            Row(
              children: [
                Expanded(
                  child: Card(
                    color: colorScheme.surfaceContainerHighest,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.shield_moon_rounded,
                                size: 20,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Resisted',
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '$_cancelCount times',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.primary,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '~${_formatMinutes(_totalSavedMinutes)} saved',
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Card(
                    color: colorScheme.surfaceContainerHighest,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.timer_outlined,
                                size: 20,
                                color: Color(0xFFFA8C42),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Screen Time',
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _formatMinutes(_totalUsedMinutes),
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFFFA8C42),
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Tracked today',
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Most Used App Highlight
            if (mostUsedApp != null) ...[
              Card(
                color: colorScheme.primaryContainer.withValues(alpha: 0.6),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: colorScheme.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18.0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colorScheme.primary.withValues(alpha: 0.2),
                        ),
                        child: Icon(
                          Icons.star_rounded,
                          color: colorScheme.primary,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'MOST USED APP TODAY',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.1,
                                color: colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _getAppName(mostUsedApp['package'] as String),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${_formatMinutes(mostUsedApp['used'] as int)} spent today • Avg session: ${_formatMinutes(mostUsedApp['avgSession'] as int)}'
                              '${(mostUsedApp['limit'] as int) > 0 ? '\nLimit: ${_formatMinutes(mostUsedApp['limit'] as int)}' : ''}',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if ((mostUsedApp['limit'] as int) > 0 &&
                          (mostUsedApp['used'] as int) >=
                              (mostUsedApp['limit'] as int))
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.redAccent,
                              width: 1,
                            ),
                          ),
                          child: const Text(
                            'LOCKED',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.redAccent,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // App Usage Leaderboard & Ranking Card
            Card(
              color: colorScheme.surfaceContainerHighest,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.leaderboard_rounded,
                              size: 20,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'App Usage Breakdown',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        Text(
                          '${_appUsageList.length} tracked',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_appUsageList.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24.0),
                        child: Center(
                          child: Text(
                            'No blocked apps configured yet.\nSelect apps in the "Blocked Apps" tab to track usage.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      )
                    else
                      ...List.generate(_appUsageList.length, (index) {
                        final item = _appUsageList[index];
                        final String pkg = item['package'] as String;
                        final int limit = item['limit'] as int;
                        final int used = item['used'] as int;
                        final int avgSession = item['avgSession'] as int;
                        final int resists = item['resists'] as int;
                        final int saved = item['savedMinutes'] as int;
                        final AppInfo? appInfo = _installedAppMap[pkg];
                        final bool hasLimit = limit > 0;
                        final bool isOver = hasLimit && used >= limit;

                        // Progress percentage relative to limit or max used app
                        final int maxUsed =
                            (_appUsageList.first['used'] as int);
                        final double progress = hasLimit
                            ? (used / limit).clamp(0.0, 1.0)
                            : maxUsed > 0
                            ? (used / maxUsed).clamp(0.0, 1.0)
                            : 0.0;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 18.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  // Rank badge
                                  Container(
                                    width: 24,
                                    height: 24,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: index == 0
                                          ? colorScheme.primary.withValues(
                                              alpha: 0.2,
                                            )
                                          : colorScheme.outline.withValues(
                                              alpha: 0.15,
                                            ),
                                    ),
                                    child: Text(
                                      '${index + 1}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: index == 0
                                            ? colorScheme.primary
                                            : colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  if (appInfo?.icon != null)
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: Image.memory(
                                        appInfo!.icon!,
                                        width: 26,
                                        height: 26,
                                      ),
                                    )
                                  else
                                    Icon(
                                      Icons.android,
                                      size: 24,
                                      color: colorScheme.primary,
                                    ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _getAppName(pkg),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    hasLimit
                                        ? '${_formatMinutes(used)} / ${_formatMinutes(limit)}'
                                        : _formatMinutes(used),
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: isOver
                                          ? Colors.redAccent
                                          : colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: progress,
                                  minHeight: 6,
                                  backgroundColor: colorScheme.outline
                                      .withValues(alpha: 0.15),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    isOver
                                        ? Colors.redAccent
                                        : colorScheme.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Avg session: ${_formatMinutes(avgSession)}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  if (resists > 0)
                                    Text(
                                      'Resisted: ${resists}x (${_formatMinutes(saved)} saved)',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: colorScheme.primary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Focus Tasks Section
            ValueListenableBuilder<List<FocusTask>>(
              valueListenable: FocusTaskService.tasksNotifier,
              builder: (context, tasks, _) {
                return Card(
                  color: colorScheme.surfaceContainerHighest,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.assignment_turned_in_rounded,
                                  size: 22,
                                  color: colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Focus Tasks',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            TextButton.icon(
                              onPressed: () => _openTaskEditor(context),
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('New Task'),
                              style: TextButton.styleFrom(
                                foregroundColor: colorScheme.primary,
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Set estimated minutes you want to spend on a task, then fulfill them in Zen Space.',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 14),
                        ValueListenableBuilder<int>(
                          valueListenable: FocusTaskService.unassignedMinutesNotifier,
                          builder: (context, unassignedMins, _) {
                            if (unassignedMins <= 0) return const SizedBox.shrink();
                            return Container(
                              margin: const EdgeInsets.only(bottom: 14),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: colorScheme.primary.withValues(alpha: 0.4)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.hourglass_top_rounded, color: colorScheme.primary, size: 20),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Unassigned Zen Focus Time: +${unassignedMins}m',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: colorScheme.onPrimaryContainer,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'You completed $unassignedMins minutes of Zen mode (e.g. from the Home Widget). Assign this focus time to fulfill one of your tasks!',
                                    style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      TextButton(
                                        onPressed: () => FocusTaskService.clearUnassignedMinutes(),
                                        child: Text(
                                          'Dismiss',
                                          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      ElevatedButton.icon(
                                        onPressed: () => _openAssignUnassignedMinutesDialog(context, unassignedMins),
                                        icon: const Icon(Icons.assignment_turned_in, size: 16),
                                        label: const Text('Assign to Task'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: colorScheme.primary,
                                          foregroundColor: colorScheme.onPrimary,
                                          visualDensity: VisualDensity.compact,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        if (tasks.isEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                            decoration: BoxDecoration(
                              color: colorScheme.surface.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.pending_actions_rounded,
                                    size: 32,
                                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'No tasks set yet',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Create a task with target minutes to concentrate in Zen Space.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  OutlinedButton.icon(
                                    onPressed: () => _openTaskEditor(context),
                                    icon: const Icon(Icons.add_task_rounded, size: 16),
                                    label: const Text('Add a Focus Task'),
                                    style: OutlinedButton.styleFrom(
                                      side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.5)),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          ...tasks.map((task) {
                            final isDone = task.isCompleted;
                            final progress = task.progress;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10.0),
                              padding: const EdgeInsets.all(14.0),
                              decoration: BoxDecoration(
                                color: colorScheme.surface.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isDone
                                      ? Colors.green.withValues(alpha: 0.4)
                                      : colorScheme.outline.withValues(alpha: 0.15),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              task.title,
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15,
                                                decoration: isDone ? TextDecoration.lineThrough : null,
                                                color: isDone
                                                    ? colorScheme.onSurfaceVariant
                                                    : colorScheme.onSurface,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '${task.spentMinutes} of ${task.estimatedMinutes} min fulfilled (${task.percentage}%)',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: isDone ? Colors.green : colorScheme.primary,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (isDone)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: Colors.green.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.check_circle_rounded, color: Colors.green, size: 14),
                                              SizedBox(width: 4),
                                              Text(
                                                'Fulfilled',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.green,
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                      else
                                        ElevatedButton.icon(
                                          onPressed: () => _promptStartZenSpace(preselectedTask: task),
                                          icon: const Icon(Icons.self_improvement, size: 16),
                                          label: const Text('Focus'),
                                          style: ElevatedButton.styleFrom(
                                            visualDensity: VisualDensity.compact,
                                            backgroundColor: colorScheme.primary,
                                            foregroundColor: colorScheme.onPrimary,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                          ),
                                        ),
                                      PopupMenuButton<String>(
                                        icon: Icon(Icons.more_vert, size: 18, color: colorScheme.onSurfaceVariant),
                                        onSelected: (action) async {
                                          if (action == 'toggle') {
                                            await FocusTaskService.toggleTaskComplete(task.id);
                                          } else if (action == 'edit') {
                                            _openTaskEditor(context, existing: task);
                                          } else if (action == 'delete') {
                                            await FocusTaskService.deleteTask(task.id);
                                          }
                                        },
                                        itemBuilder: (ctx) => [
                                          PopupMenuItem(
                                            value: 'toggle',
                                            child: Text(isDone ? 'Mark Incomplete' : 'Mark Fulfilled'),
                                          ),
                                          const PopupMenuItem(
                                            value: 'edit',
                                            child: Text('Edit Minutes/Title'),
                                          ),
                                          const PopupMenuItem(
                                            value: 'delete',
                                            child: Text('Delete Task', style: TextStyle(color: Colors.redAccent)),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: progress,
                                      minHeight: 6,
                                      backgroundColor: colorScheme.outline.withValues(alpha: 0.15),
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        isDone ? Colors.green : colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 16),

            // Zen Space Card
            if (_zenModeEndTime > DateTime.now().millisecondsSinceEpoch)
              Card(
                color: colorScheme.primaryContainer.withValues(alpha: 0.7),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: colorScheme.primary.withValues(alpha: 0.4),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20.0,
                    vertical: 24.0,
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.self_improvement_rounded,
                            size: 28,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Zen Space Active',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                              color: colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _formatCountdown(_zenModeEndTime),
                        style: Theme.of(context).textTheme.displaySmall
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2.0,
                              color: colorScheme.onPrimaryContainer,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Ends at ${_formatTime(DateTime.fromMillisecondsSinceEpoch(_zenModeEndTime))}',
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      ValueListenableBuilder<FocusTask?>(
                        valueListenable: FocusTaskService.activeTaskNotifier,
                        builder: (context, activeTask, _) {
                          if (activeTask == null) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 14.0),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: colorScheme.surface.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.track_changes_rounded, size: 16, color: colorScheme.primary),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Concentrating on:',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          activeTask.title,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: activeTask.progress,
                                      minHeight: 6,
                                      backgroundColor: colorScheme.outline.withValues(alpha: 0.15),
                                      valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${activeTask.spentMinutes} / ${activeTask.estimatedMinutes} min fulfilled (${activeTask.percentage}%)',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          OutlinedButton(
                            onPressed: _exitZenSpace,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 10,
                              ),
                              side: BorderSide(
                                color: colorScheme.outline.withValues(alpha: 0.5),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('Exit Early'),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton.icon(
                            onPressed: _completeTaskEarly,
                            icon: const Icon(Icons.check, size: 16),
                            label: const Text('Mark Goal Fulfilled'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colorScheme.primary,
                              foregroundColor: colorScheme.onPrimary,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              )
            else
              Card(
                color: colorScheme.surfaceContainerHighest,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      Icon(
                        Icons.self_improvement_rounded,
                        size: 36,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          const Text(
                            'Enter Zen Space',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Also available as widget',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Block all apps except your Zen Whitelist.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        children: [15, 30, 60, 120].map((mins) {
                          final isSelected = _selectedZenMinutes == mins;
                          return ChoiceChip(
                            label: Text(
                              mins >= 60 ? '${mins ~/ 60}h' : '${mins}m',
                            ),
                            selected: isSelected,
                            selectedColor: colorScheme.primaryContainer,
                            labelStyle: TextStyle(
                              color: isSelected
                                  ? colorScheme.onPrimaryContainer
                                  : colorScheme.onSurface,
                            ),
                            onSelected: (selected) {
                              if (selected) {
                                setState(() => _selectedZenMinutes = mins);
                              }
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => _enterZenSpace(_selectedZenMinutes),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorScheme.primary,
                          foregroundColor: colorScheme.onPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Start Zen Space'),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // Testing buttons
            /* Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Test Timer'),
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();
                    final currentWaitTime = prefs.getInt('wait_time_seconds') ?? 10;
                    if (!context.mounted) return;

                    final dynamic proceeded = await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => InterventionScreen(
                          waitTimeSeconds: currentWaitTime,
                          targetAppName: 'Instagram (Test)',
                          usedMinutes: 10,
                          limitMinutes: 30,
                        ),
                      ),
                    );

                    if (proceeded == false || proceeded == null) {
                      await StatsService.recordResist('com.instagram.android');
                      await _loadStats();
                    }
                  },
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  icon: const Icon(Icons.lock_clock),
                  label: const Text('Test Limit Block'),
                  onPressed: () async {
                    if (!context.mounted) return;

                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const InterventionScreen(
                          waitTimeSeconds: 999999,
                          targetAppName: 'Instagram (Test)',
                          isLimitBlock: true,
                          usedMinutes: 30,
                          limitMinutes: 30,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ), */
          ],
        ),
      ),
    );
  }
}
class _TaskEditorSheet extends StatefulWidget {
  final FocusTask? existing;

  const _TaskEditorSheet({this.existing});

  @override
  State<_TaskEditorSheet> createState() => _TaskEditorSheetState();
}

class _TaskEditorSheetState extends State<_TaskEditorSheet> {
  late TextEditingController _titleController;
  late int _estimatedMinutes;
  final TextEditingController _customMinutesController = TextEditingController();
  bool _isCustom = false;

  final List<int> _presets = [15, 25, 30, 45, 60, 90, 120];

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    _titleController = TextEditingController(text: ex?.title ?? '');
    _estimatedMinutes = ex?.estimatedMinutes ?? 30;
    if (!_presets.contains(_estimatedMinutes)) {
      _isCustom = true;
      _customMinutesController.text = _estimatedMinutes.toString();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _customMinutesController.dispose();
    super.dispose();
  }

  void _save() async {
    final title = _titleController.text.trim().isEmpty
        ? 'Focus Task'
        : _titleController.text.trim();

    int minutes = _estimatedMinutes;
    if (_isCustom) {
      final parsed = int.tryParse(_customMinutesController.text.trim());
      if (parsed != null && parsed > 0) {
        minutes = parsed;
      }
    }

    if (widget.existing != null) {
      final updated = widget.existing!.copyWith(
        title: title,
        estimatedMinutes: minutes,
      );
      await FocusTaskService.updateTask(updated);
    } else {
      await FocusTaskService.createTask(title, minutes);
    }

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 20, 24, 20 + bottomInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.outline.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            widget.existing != null ? 'Edit Focus Task' : 'New Focus Task',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Specify how many minutes you want to spend concentrating on this task.',
            style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _titleController,
            autofocus: widget.existing == null,
            decoration: InputDecoration(
              labelText: 'Task Name',
              hintText: 'e.g. Study Physics, Write essay, Review code',
              prefixIcon: const Icon(Icons.edit_note_rounded),
              filled: true,
              fillColor: colorScheme.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Target Estimated Minutes',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ..._presets.map((mins) {
                final isSelected = !_isCustom && _estimatedMinutes == mins;
                return ChoiceChip(
                  label: Text(mins >= 60 ? '${mins ~/ 60}h ${mins % 60 > 0 ? '${mins % 60}m' : ''}'.trim() : '${mins}m'),
                  selected: isSelected,
                  selectedColor: colorScheme.primaryContainer,
                  labelStyle: TextStyle(
                    color: isSelected ? colorScheme.onPrimaryContainer : colorScheme.onSurface,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _isCustom = false;
                        _estimatedMinutes = mins;
                      });
                    }
                  },
                );
              }),
              ChoiceChip(
                label: const Text('Custom'),
                selected: _isCustom,
                selectedColor: colorScheme.primaryContainer,
                labelStyle: TextStyle(
                  color: _isCustom ? colorScheme.onPrimaryContainer : colorScheme.onSurface,
                  fontWeight: _isCustom ? FontWeight.bold : FontWeight.normal,
                ),
                onSelected: (selected) {
                  setState(() {
                    _isCustom = true;
                  });
                },
              ),
            ],
          ),
          if (_isCustom) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _customMinutesController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Custom Target Minutes',
                hintText: 'e.g. 40',
                suffixText: 'minutes',
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (val) {
                final p = int.tryParse(val.trim());
                if (p != null && p > 0) {
                  _estimatedMinutes = p;
                }
              },
            ),
          ],
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              widget.existing != null ? 'Update Task' : 'Create Task',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectTaskForZenSheet extends StatefulWidget {
  final List<FocusTask> tasks;
  final FocusTask? preselectedTask;
  final int initialMinutes;
  final bool isAssigningToActiveZen;

  const _SelectTaskForZenSheet({
    required this.tasks,
    this.preselectedTask,
    required this.initialMinutes,
    this.isAssigningToActiveZen = false,
  });

  @override
  State<_SelectTaskForZenSheet> createState() => _SelectTaskForZenSheetState();
}

class _SelectTaskForZenSheetState extends State<_SelectTaskForZenSheet> {
  FocusTask? _selectedTask;
  late int _sessionMinutes;
  bool _setAlarm = true;
  bool _silencePhone = false;
  bool _isCreatingInline = false;

  final TextEditingController _newTitleController = TextEditingController();
  final TextEditingController _newMinutesController = TextEditingController(text: '30');

  final List<int> _presetDurations = [15, 25, 30, 45, 60, 90, 120];

  @override
  void initState() {
    super.initState();
    _sessionMinutes = widget.initialMinutes;
    _silencePhone = DndService.isSilenceEnabledNotifier.value;
    if (widget.preselectedTask != null) {
      _selectedTask = widget.preselectedTask;
    } else {
      final uncompleted = widget.tasks.where((t) => !t.isCompleted).toList();
      _selectedTask = uncompleted.isNotEmpty ? uncompleted.first : null;
    }

    if (_selectedTask != null && _selectedTask!.remainingMinutes > 0) {
      // Suggest duration matching task remaining minutes if reasonable
      if (_presetDurations.contains(_selectedTask!.remainingMinutes)) {
        _sessionMinutes = _selectedTask!.remainingMinutes;
      }
    }
  }

  @override
  void dispose() {
    _newTitleController.dispose();
    _newMinutesController.dispose();
    super.dispose();
  }

  void _onTaskChosen(FocusTask task) {
    setState(() {
      _selectedTask = task;
      if (task.remainingMinutes > 0 && _presetDurations.contains(task.remainingMinutes)) {
        _sessionMinutes = task.remainingMinutes;
      }
    });
  }

  void _confirmSelection() {
    if (_selectedTask == null) return;
    Navigator.of(context).pop({
      'task': _selectedTask,
      'minutes': _sessionMinutes,
      'setAlarm': _setAlarm,
      'silencePhone': _silencePhone,
    });
  }

  void _saveInlineTask() async {
    final title = _newTitleController.text.trim();
    if (title.isEmpty) return;
    final mins = int.tryParse(_newMinutesController.text.trim()) ?? 30;
    final created = await FocusTaskService.createTask(title, mins);
    setState(() {
      _isCreatingInline = false;
      _selectedTask = created;
      _sessionMinutes = mins.clamp(15, 120);
    });
  }

  Future<bool> _requestDndPermissionIfNeeded() async {
    final granted = await DndService.isDndPermissionGranted();
    if (granted) return true;
    if (!mounted) return false;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Do Not Disturb Access'),
        content: const Text(
          'To silence notifications and phone calls, Android requires Do Not Disturb access permission.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx, true);
              DndService.openDndSettings();
            },
            child: const Text('Grant Access'),
          ),
        ],
      ),
    );
    return proceed == true;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final availableTasks = FocusTaskService.tasksNotifier.value;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 20, 24, 20 + bottomInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.outline.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.self_improvement_rounded, color: colorScheme.primary, size: 28),
              const SizedBox(width: 10),
              Text(
                widget.isAssigningToActiveZen ? 'Assign Focus Task' : 'Enter Zen Space',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            widget.isAssigningToActiveZen
                ? 'Select which task you are working on during this active Zen session.'
                : 'Choose which task you are concentrating on to fulfill its estimated minutes.',
            style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),

          // Task Selection Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Select Focus Task',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              if (!_isCreatingInline)
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _isCreatingInline = true;
                    });
                  },
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add Task'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: colorScheme.primary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Inline Task Creator if requested or if tasks list is empty
          if (_isCreatingInline || availableTasks.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colorScheme.primary.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Create New Task to Focus On',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _newTitleController,
                    decoration: InputDecoration(
                      hintText: 'Task Name (e.g. Study Chemistry)',
                      filled: true,
                      fillColor: colorScheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _newMinutesController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Target Minutes',
                            suffixText: 'min',
                            filled: true,
                            fillColor: colorScheme.surface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: _saveInlineTask,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorScheme.primary,
                          foregroundColor: colorScheme.onPrimary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        ),
                        child: const Text('Save & Select'),
                      ),
                    ],
                  ),
                ],
              ),
            ),

          // List of selectable tasks
          if (availableTasks.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: availableTasks.length,
                itemBuilder: (ctx, idx) {
                  final t = availableTasks[idx];
                  final isSelected = _selectedTask?.id == t.id;
                  final isDone = t.isCompleted;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? colorScheme.primaryContainer.withValues(alpha: 0.7)
                          : colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? colorScheme.primary : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                      leading: Icon(
                        isSelected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                      ),
                      title: Text(
                        t.title,
                        style: TextStyle(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                          decoration: isDone ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      subtitle: Text(
                        '${t.spentMinutes} / ${t.estimatedMinutes} min fulfilled (${t.percentage}%)',
                        style: TextStyle(
                          fontSize: 11,
                          color: isSelected ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
                        ),
                      ),
                      trailing: isDone
                          ? const Icon(Icons.check_circle, color: Colors.green, size: 18)
                          : Text(
                              '${t.remainingMinutes}m left',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                            ),
                      onTap: () => _onTaskChosen(t),
                    ),
                  );
                },
              ),
            ),

          const SizedBox(height: 18),

          if (!widget.isAssigningToActiveZen) ...[
          // Session Duration Picker
          Text(
            'Zen Session Duration',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _presetDurations.map((mins) {
              final isSelected = _sessionMinutes == mins;
              return ChoiceChip(
                label: Text(mins >= 60 ? '${mins ~/ 60}h ${mins % 60 > 0 ? '${mins % 60}m' : ''}'.trim() : '${mins}m'),
                selected: isSelected,
                selectedColor: colorScheme.primaryContainer,
                labelStyle: TextStyle(
                  color: isSelected ? colorScheme.onPrimaryContainer : colorScheme.onSurface,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
                onSelected: (selected) {
                  if (selected) {
                    setState(() {
                      _sessionMinutes = mins;
                    });
                  }
                },
              );
            }).toList(),
          ),

          const SizedBox(height: 14),

          // Set Alarm Option
          SwitchListTile(
            title: const Text('Set alarm when time is up', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            subtitle: const Text('Ring alarm so you know your focus session has ended', style: TextStyle(fontSize: 12)),
            secondary: Icon(Icons.alarm, color: colorScheme.primary),
            value: _setAlarm,
            activeTrackColor: colorScheme.primary,
            contentPadding: EdgeInsets.zero,
            onChanged: (v) => setState(() => _setAlarm = v),
          ),
          SwitchListTile(
            title: const Text('Silence phone (Do Not Disturb)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            subtitle: const Text('Mute calls and notification alerts while in Zen Space', style: TextStyle(fontSize: 12)),
            secondary: Icon(Icons.do_not_disturb_on_rounded, color: colorScheme.primary),
            value: _silencePhone,
            activeTrackColor: colorScheme.primary,
            contentPadding: EdgeInsets.zero,
            onChanged: (v) async {
              if (v) {
                final allowed = await _requestDndPermissionIfNeeded();
                if (!allowed) return;
              }
              if (!mounted) return;
              setState(() => _silencePhone = v);
            },
          ),
          ],

          const SizedBox(height: 18),

          // Start Button
          ElevatedButton.icon(
            onPressed: _selectedTask != null ? _confirmSelection : null,
            icon: const Icon(Icons.self_improvement_rounded),
            label: Text(
              _selectedTask != null
                  ? (widget.isAssigningToActiveZen
                      ? 'Assign to Current Session'
                      : 'Start Zen Space (${_sessionMinutes}m)')
                  : 'Select or create a task first',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
