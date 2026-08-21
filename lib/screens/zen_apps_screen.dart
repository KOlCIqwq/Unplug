import 'package:flutter/material.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

class ZenAppsScreen extends StatefulWidget {
  const ZenAppsScreen({super.key});

  @override
  State<ZenAppsScreen> createState() => _ZenAppsScreenState();
}

class _ZenAppsScreenState extends State<ZenAppsScreen> {
  List<AppInfo> _apps = [];
  bool _isLoading = true;
  Set<String> _zenAppPackages = {};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadBlockedApps();
    _loadApps();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadBlockedApps() async {
    final prefs = await SharedPreferences.getInstance();
    final zenAppsString = prefs.getString('zen_whitelisted_apps_string') ?? '';
    setState(() {
      _zenAppPackages = zenAppsString
          .split(',')
          .where((s) => s.isNotEmpty)
          .toSet();
    });
  }

  Future<void> _saveZenApps() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('zen_whitelisted_apps', _zenAppPackages.toList());
    await prefs.setString(
      'zen_whitelisted_apps_string',
      _zenAppPackages.join(','),
    );
  }

  Future<void> _loadApps() async {
    try {
      if (!kIsWeb && Platform.isAndroid) {
        List<AppInfo> apps = await InstalledApps.getInstalledApps(
          excludeSystemApps: true,
          withIcon: true,
        );
        setState(() {
          _apps = apps;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _toggleAppAllow(String packageName) {
    setState(() {
      if (_zenAppPackages.contains(packageName)) {
        _zenAppPackages.remove(packageName);
      } else {
        _zenAppPackages.add(packageName);
      }
    });
    _saveZenApps();
  }

  List<AppInfo> get _filteredAndSortedApps {
    final query = _searchQuery.trim().toLowerCase();
    final filtered = _apps.where((app) {
      if (query.isEmpty) return true;
      return app.name.toLowerCase().contains(query) ||
          app.packageName.toLowerCase().contains(query);
    }).toList();

    filtered.sort((a, b) {
      final aAllowed = _zenAppPackages.contains(a.packageName);
      final bAllowed = _zenAppPackages.contains(b.packageName);

      // Allowed Zen apps pushed to the top
      if (aAllowed != bAllowed) {
        return aAllowed ? -1 : 1;
      }

      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final displayApps = _filteredAndSortedApps;

    return Scaffold(
      appBar: AppBar(title: const Text('Allowed Zen Apps'), elevation: 0),
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
                          hintText: 'Search apps...',
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
                                '${_zenAppPackages.length} allowed in Zen Space',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _zenAppPackages.isNotEmpty ? colorScheme.primary : colorScheme.onSurfaceVariant,
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
                            final isAllowed = _zenAppPackages.contains(
                              packageName,
                            );

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
                              title: Text(
                                app.name,
                                style: TextStyle(
                                  fontWeight: isAllowed
                                      ? FontWeight.bold
                                      : FontWeight.w500,
                                ),
                              ),
                              subtitle: Text(
                                packageName,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              trailing: Switch(
                                value: isAllowed,
                                activeTrackColor: colorScheme.primary,
                                onChanged: (value) =>
                                    _toggleAppAllow(packageName),
                              ),
                              onTap: () => _toggleAppAllow(packageName),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
