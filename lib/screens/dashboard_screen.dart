import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:async';
import 'intervention_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with WidgetsBindingObserver {
  int _cancelCount = 0;
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
        final apps = await InstalledApps.getInstalledApps(excludeSystemApps: true, withIcon: true);
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
    final dateKey = _getTodayDateKey();
    final blocked = prefs.getStringList('blocked_apps') ?? [];

    final List<Map<String, dynamic>> usageList = [];
    int totalMins = 0;

    for (final pkg in blocked) {
      final limitMins = prefs.getInt('limit_$pkg') ?? 0;
      final usedMs = prefs.getInt('usage_${dateKey}_$pkg') ?? 0;
      final usedMins = (usedMs / (60 * 1000)).toInt();
      totalMins += usedMins;

      if (limitMins > 0 || usedMins > 0) {
        usageList.add({
          'package': pkg,
          'limit': limitMins,
          'used': usedMins,
        });
      }
    }

    // Sort by most used first
    usageList.sort((a, b) => (b['used'] as int).compareTo(a['used'] as int));

    if (mounted) {
      setState(() {
        _cancelCount = prefs.getInt('cancel_count') ?? 0;
        _zenModeEndTime = prefs.getInt('zen_mode_end_time') ?? 0;
        _appUsageList = usageList;
        _totalUsedMinutes = totalMins;
        _isLoading = false;
      });
    }

    _zenTimer?.cancel();
    _zenTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_zenModeEndTime > 0 && DateTime.now().millisecondsSinceEpoch > _zenModeEndTime) {
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

  Future<void> _incrementCancelCount() async {
    final prefs = await SharedPreferences.getInstance();
    int newCount = _cancelCount + 1;
    await prefs.setInt('cancel_count', newCount);
    if (mounted) {
      setState(() {
        _cancelCount = newCount;
      });
    }
  }

  Future<void> _enterZenSpace(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    final endTime = DateTime.now().millisecondsSinceEpoch + (minutes * 60 * 1000);
    await prefs.setInt('zen_mode_end_time', endTime);
    if (mounted) {
      setState(() {
        _zenModeEndTime = endTime;
      });
    }
  }

  Future<void> _exitZenSpace() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('zen_mode_end_time', 0);
    if (mounted) {
      setState(() {
        _zenModeEndTime = 0;
      });
    }
  }

  String _formatTime(DateTime time) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return '${twoDigits(time.hour)}:${twoDigits(time.minute)}';
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
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final int estimatedMinutesSaved = _cancelCount * 5;
    final mostUsedApp = _appUsageList.isNotEmpty && (_appUsageList.first['used'] as int) > 0
        ? _appUsageList.first
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistics & Overview'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Overview Cards (Saved Time & Tracked Usage)
            Row(
              children: [
                Expanded(
                  child: Card(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.shield_moon, size: 20, color: Colors.teal),
                              const SizedBox(width: 8),
                              Text(
                                'Resisted',
                                style: TextStyle(color: Colors.grey[400], fontSize: 13),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '$_cancelCount times',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.tealAccent,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '~$estimatedMinutesSaved mins saved',
                            style: const TextStyle(fontSize: 12, color: Colors.white60),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Card(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.timer_outlined, size: 20, color: Colors.amberAccent),
                              const SizedBox(width: 8),
                              Text(
                                'Screen Time',
                                style: TextStyle(color: Colors.grey[400], fontSize: 13),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _formatMinutes(_totalUsedMinutes),
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.amberAccent,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Tracked today',
                            style: const TextStyle(fontSize: 12, color: Colors.white60),
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
                color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.6),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18.0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                        ),
                        child: const Icon(Icons.star_rounded, color: Colors.amberAccent, size: 28),
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
                                color: Theme.of(context).colorScheme.primary,
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
                              '${_formatMinutes(mostUsedApp['used'] as int)} spent today'
                              '${(mostUsedApp['limit'] as int) > 0 ? ' (Limit: ${_formatMinutes(mostUsedApp['limit'] as int)})' : ''}',
                              style: const TextStyle(fontSize: 12, color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                      if ((mostUsedApp['limit'] as int) > 0 &&
                          (mostUsedApp['used'] as int) >= (mostUsedApp['limit'] as int))
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.redAccent, width: 1),
                          ),
                          child: const Text(
                            'LOCKED',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.redAccent),
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
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                            const Icon(Icons.leaderboard_rounded, size: 20, color: Colors.teal),
                            const SizedBox(width: 8),
                            Text(
                              'App Usage Breakdown',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '${_appUsageList.length} tracked',
                          style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_appUsageList.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24.0),
                        child: Center(
                          child: Text(
                            'No blocked apps configured yet.\nSelect apps in the "Blocked Apps" tab to track usage.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white54, fontSize: 13),
                          ),
                        ),
                      )
                    else
                      ...List.generate(_appUsageList.length, (index) {
                        final item = _appUsageList[index];
                        final String pkg = item['package'] as String;
                        final int limit = item['limit'] as int;
                        final int used = item['used'] as int;
                        final AppInfo? appInfo = _installedAppMap[pkg];
                        final bool hasLimit = limit > 0;
                        final bool isOver = hasLimit && used >= limit;

                        // Progress percentage relative to limit or max used app
                        final int maxUsed = (_appUsageList.first['used'] as int);
                        final double progress = hasLimit
                            ? (used / limit).clamp(0.0, 1.0)
                            : maxUsed > 0
                                ? (used / maxUsed).clamp(0.0, 1.0)
                                : 0.0;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16.0),
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
                                          ? Colors.amber.withValues(alpha: 0.2)
                                          : index == 1
                                              ? Colors.grey.withValues(alpha: 0.2)
                                              : index == 2
                                                  ? Colors.brown.withValues(alpha: 0.2)
                                                  : Colors.white10,
                                    ),
                                    child: Text(
                                      '${index + 1}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: index == 0
                                            ? Colors.amberAccent
                                            : index == 1
                                                ? Colors.white70
                                                : index == 2
                                                    ? Colors.orangeAccent
                                                    : Colors.white54,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  if (appInfo?.icon != null)
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: Image.memory(appInfo!.icon!, width: 26, height: 26),
                                    )
                                  else
                                    const Icon(Icons.android, size: 24, color: Colors.teal),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _getAppName(pkg),
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                    ),
                                  ),
                                  Text(
                                    hasLimit
                                        ? '${_formatMinutes(used)} / ${_formatMinutes(limit)}'
                                        : _formatMinutes(used),
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: isOver ? Colors.redAccent : Colors.tealAccent,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: progress,
                                  minHeight: 6,
                                  backgroundColor: Colors.white10,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    isOver
                                        ? Colors.redAccent
                                        : index == 0
                                            ? Colors.amberAccent
                                            : Colors.teal,
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
            ),

            const SizedBox(height: 16),

            // Zen Space Card
            if (_zenModeEndTime > DateTime.now().millisecondsSinceEpoch)
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      const Icon(Icons.self_improvement, size: 40),
                      const SizedBox(height: 8),
                      const Text('Zen Space Active', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(
                        'Ends at ${_formatTime(DateTime.fromMillisecondsSinceEpoch(_zenModeEndTime))}',
                        style: const TextStyle(fontSize: 15),
                      ),
                      const SizedBox(height: 14),
                      OutlinedButton(
                        onPressed: _exitZenSpace,
                        child: const Text('Exit Early'),
                      ),
                    ],
                  ),
                ),
              )
            else
              Card(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      const Icon(Icons.self_improvement, size: 36, color: Colors.teal),
                      const SizedBox(height: 8),
                      const Text('Enter Zen Space', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      const Text(
                        'Block all apps except your Zen Whitelist.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        children: [15, 30, 60, 120].map((mins) {
                          final isSelected = _selectedZenMinutes == mins;
                          return ChoiceChip(
                            label: Text(mins >= 60 ? '${mins ~/ 60}h' : '${mins}m'),
                            selected: isSelected,
                            selectedColor: Theme.of(context).colorScheme.primary,
                            onSelected: (selected) {
                              if (selected) setState(() => _selectedZenMinutes = mins);
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => _enterZenSpace(_selectedZenMinutes),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Theme.of(context).colorScheme.onPrimary,
                        ),
                        child: const Text('Start Zen Space'),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // Testing buttons
            Row(
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

                    if (proceeded == false) {
                      _incrementCancelCount();
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
            ),
          ],
        ),
      ),
    );
  }
}
