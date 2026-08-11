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

  @override
  void initState() {
    super.initState();
    _loadBlockedApps();
    _loadApps();
  }

  Future<void> _loadBlockedApps() async {
    final prefs = await SharedPreferences.getInstance();
    final zenAppsString = prefs.getString('zen_whitelisted_apps_string') ?? '';
    setState(() {
      _zenAppPackages = zenAppsString.split(',').where((s) => s.isNotEmpty).toSet();
    });
  }

  Future<void> _saveZenApps() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('zen_whitelisted_apps', _zenAppPackages.toList());
    await prefs.setString('zen_whitelisted_apps_string', _zenAppPackages.join(','));
  }

  Future<void> _loadApps() async {
    try {
      if (!kIsWeb && Platform.isAndroid) {
        List<AppInfo> apps = await InstalledApps.getInstalledApps(excludeSystemApps: true, withIcon: true);
        apps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        setState(() {
          _apps = apps;
          _isLoading = false;
        });
      } else {
        // Mock data for testing on non-Android platforms
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Allowed Zen Apps'),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : !kIsWeb && !Platform.isAndroid
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text(
                      'App loading is only supported on Android. Please run this app on an Android emulator or device to see your installed apps.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: _apps.length,
                  itemBuilder: (context, index) {
                    final app = _apps[index];
                    final packageName = app.packageName;
                    final isAllowed = _zenAppPackages.contains(packageName);
                    
                    return ListTile(
                      leading: app.icon != null
                          ? Image.memory(app.icon!, width: 40, height: 40)
                          : const Icon(Icons.android),
                      title: Text(app.name),
                      subtitle: Text(packageName, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      trailing: Switch(
                        value: isAllowed,
                        activeThumbColor: Theme.of(context).colorScheme.primary,
                        onChanged: (value) => _toggleAppAllow(packageName),
                      ),
                      onTap: () => _toggleAppAllow(packageName),
                    );
                  },
                ),
    );
  }
}
