import 'package:flutter/material.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

class AppSelectorScreen extends StatefulWidget {
  const AppSelectorScreen({super.key});

  @override
  State<AppSelectorScreen> createState() => _AppSelectorScreenState();
}

class _AppSelectorScreenState extends State<AppSelectorScreen> {
  bool _isLoading = true;
  List<AppInfo> _apps = [];
  Set<String> _blockedAppPackages = {};
  Map<String, int> _appLimits = {};
  Map<String, int> _appUsageToday = {};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _getTodayDateKey() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }

  Future<void> _loadData() async {
    await _loadBlockedApps();
    await _loadApps();
  }

  Future<void> _loadBlockedApps() async {
    final prefs = await SharedPreferences.getInstance();
    final blocked = (prefs.getStringList('blocked_apps') ?? []).toSet();
    final dateKey = _getTodayDateKey();

    final Map<String, int> limits = {};
    final Map<String, int> usage = {};
    for (final pkg in blocked) {
      limits[pkg] = prefs.getInt('limit_$pkg') ?? 0;
      final usedMs = prefs.getInt('usage_${dateKey}_$pkg') ?? 0;
      usage[pkg] = (usedMs / (60 * 1000)).toInt();
    }

    if (mounted) {
      setState(() {
        _blockedAppPackages = blocked;
        _appLimits = limits;
        _appUsageToday = usage;
      });
    }
  }

  Future<void> _saveBlockedApps() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('blocked_apps', _blockedAppPackages.toList());
    await prefs.setString('blocked_apps_string', _blockedAppPackages.join(','));
  }

  Future<void> _loadApps() async {
    try {
      if (!kIsWeb && Platform.isAndroid) {
        List<AppInfo> apps = await InstalledApps.getInstalledApps(
          excludeSystemApps: true,
          withIcon: true,
        );
        if (mounted) {
          setState(() {
            _apps = apps;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _toggleAppBlock(String packageName) {
    setState(() {
      if (_blockedAppPackages.contains(packageName)) {
        _blockedAppPackages.remove(packageName);
      } else {
        _blockedAppPackages.add(packageName);
      }
    });
    _saveBlockedApps();
  }

  Future<void> _setAppDailyLimit(
    String packageName,
    String appName,
    int currentLimit,
  ) async {
    int selectedLimit = currentLimit;
    final presets = [0, 15, 30, 45, 60, 90, 120];
    final colorScheme = Theme.of(context).colorScheme;

    final result = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                top: 24,
                left: 24,
                right: 24,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.timer_outlined, color: colorScheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Daily Limit: $appName',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'When this limit is reached, opening the app will be completely blocked for the rest of today.',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: presets.map((mins) {
                      final isSelected = selectedLimit == mins;
                      final label = mins == 0
                          ? 'No Limit (∞)'
                          : mins >= 60
                          ? '${mins ~/ 60}h${mins % 60 > 0 ? ' ${mins % 60}m' : ''}'
                          : '${mins}m';
                      return ChoiceChip(
                        label: Text(label),
                        selected: isSelected,
                        selectedColor: colorScheme.primaryContainer,
                        labelStyle: TextStyle(
                          color: isSelected
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onSurface,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                        onSelected: (selected) {
                          if (selected) {
                            setSheetState(() {
                              selectedLimit = mins;
                            });
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () =>
                            Navigator.of(context).pop(selectedLimit),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorScheme.primary,
                          foregroundColor: colorScheme.onPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Save Limit'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (result != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('limit_$packageName', result);
      setState(() {
        _appLimits[packageName] = result;
      });
    }
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

  List<AppInfo> get _filteredAndSortedApps {
    final query = _searchQuery.trim().toLowerCase();
    final filtered = _apps.where((app) {
      if (query.isEmpty) return true;
      return app.name.toLowerCase().contains(query) ||
          app.packageName.toLowerCase().contains(query);
    }).toList();

    filtered.sort((a, b) {
      final aBlocked = _blockedAppPackages.contains(a.packageName);
      final bBlocked = _blockedAppPackages.contains(b.packageName);
      final aLimit = _appLimits[a.packageName] ?? 0;
      final bLimit = _appLimits[b.packageName] ?? 0;

      // Priority ranking:
      // 2: Blocked with daily limit > 0 (Limited apps at the very top)
      // 1: Blocked without daily limit
      // 0: Unblocked
      final aScore = aBlocked ? (aLimit > 0 ? 2 : 1) : 0;
      final bScore = bBlocked ? (bLimit > 0 ? 2 : 1) : 0;

      if (aScore != bScore) {
        return bScore.compareTo(aScore); // Higher priority first
      }

      // Tie-breaker: alphabetical order by app name
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final displayApps = _filteredAndSortedApps;
    /*     final limitedCount = _blockedAppPackages.where((pkg) => (_appLimits[pkg] ?? 0) > 0).length;
    final totalBlockedCount = _blockedAppPackages.length; */

    return Scaffold(
      appBar: AppBar(title: const Text('Select Apps to Block'), elevation: 0),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : !kIsWeb && !Platform.isAndroid
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'App loading is only supported on Android. Please run this app on an Android emulator or device to see your installed apps.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          : Column(
              children: [
                // Search Bar & Stats Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _searchController,
                        onChanged: (value) {
                          setState(() {
                            _searchQuery = value;
                          });
                        },
                        decoration: InputDecoration(
                          hintText: 'Search installed apps...',
                          hintStyle: TextStyle(
                            color: colorScheme.onSurfaceVariant.withValues(
                              alpha: 0.7,
                            ),
                            fontSize: 14,
                          ),
                          prefixIcon: Icon(
                            Icons.search_rounded,
                            color: colorScheme.primary,
                          ),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.clear_rounded,
                                    size: 20,
                                  ),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {
                                      _searchQuery = '';
                                    });
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: colorScheme.surfaceContainerHighest,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      /* Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                totalBlockedCount == 0
                                    ? 'No apps blocked yet'
                                    : '$totalBlockedCount blocked ($limitedCount with limits)',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: totalBlockedCount > 0 ? colorScheme.primary : colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '${displayApps.length} apps',
                                style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ), */
                    ],
                  ),
                ),

                /* const Divider(height: 1), */

                // App List
                Expanded(
                  child: displayApps.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.search_off_rounded,
                                size: 48,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No apps found matching "$_searchQuery"',
                                style: TextStyle(
                                  fontSize: 15,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: displayApps.length,
                          itemBuilder: (context, index) {
                            final app = displayApps[index];
                            final packageName = app.packageName;
                            final isBlocked = _blockedAppPackages.contains(
                              packageName,
                            );
                            final limit = _appLimits[packageName] ?? 0;
                            final used = _appUsageToday[packageName] ?? 0;
                            final isOver = limit > 0 && used >= limit;

                            return ListTile(
                              leading: app.icon != null
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.memory(
                                        app.icon!,
                                        width: 40,
                                        height: 40,
                                      ),
                                    )
                                  : Icon(
                                      Icons.android,
                                      color: colorScheme.primary,
                                    ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      app.name,
                                      style: TextStyle(
                                        fontWeight: (isBlocked || limit > 0)
                                            ? FontWeight.bold
                                            : FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  if (limit > 0)
                                    Container(
                                      margin: const EdgeInsets.only(left: 6),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: colorScheme.primaryContainer,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        _formatMinutes(limit),
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: colorScheme.onPrimaryContainer,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              subtitle: isBlocked
                                  ? Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const SizedBox(height: 2),
                                        Text(
                                          limit > 0
                                              ? 'Daily limit: ${_formatMinutes(limit)} • Used: ${_formatMinutes(used)} today'
                                              : 'No daily limit • Used: ${_formatMinutes(used)} today',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: isOver
                                                ? Colors.redAccent
                                                : colorScheme.onSurfaceVariant,
                                            fontWeight: isOver
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                          ),
                                        ),
                                        if (isOver) ...[
                                          const SizedBox(height: 2),
                                          const Text(
                                            '🔒 Limit reached - Hard blocked',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.redAccent,
                                            ),
                                          ),
                                        ],
                                      ],
                                    )
                                  : Text(
                                      packageName,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isBlocked)
                                    IconButton(
                                      icon: Icon(
                                        limit > 0
                                            ? Icons.timer
                                            : Icons.timer_outlined,
                                        color: limit > 0
                                            ? colorScheme.primary
                                            : colorScheme.onSurfaceVariant,
                                        size: 22,
                                      ),
                                      tooltip: 'Set Daily Limit',
                                      onPressed: () => _setAppDailyLimit(
                                        packageName,
                                        app.name,
                                        limit,
                                      ),
                                    ),
                                  Switch(
                                    value: isBlocked,
                                    activeTrackColor: colorScheme.primary,
                                    onChanged: (value) =>
                                        _toggleAppBlock(packageName),
                                  ),
                                ],
                              ),
                              onTap: isBlocked
                                  ? () => _setAppDailyLimit(
                                      packageName,
                                      app.name,
                                      limit,
                                    )
                                  : () => _toggleAppBlock(packageName),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
