import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:async';

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
    _loadAllData();
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

  Future<void> _enterZenSpace(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    final endTime =
        DateTime.now().millisecondsSinceEpoch + (minutes * 60 * 1000);
    await prefs.setInt('zen_mode_end_time', endTime);
    if (mounted) {
      setState(() {
        _zenModeEndTime = endTime;
      });
    }
    _notifyWidgetUpdate();
  }

  Future<void> _exitZenSpace() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('zen_mode_end_time', 0);
    if (mounted) {
      setState(() {
        _zenModeEndTime = 0;
      });
    }
    _notifyWidgetUpdate();
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
                      const SizedBox(height: 18),
                      OutlinedButton(
                        onPressed: _exitZenSpace,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
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
