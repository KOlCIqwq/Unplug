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

  @override
  void initState() {
    super.initState();
    _loadBlockedApps();
    _loadApps();
  }

  Future<void> _loadBlockedApps() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _blockedAppPackages = (prefs.getStringList('blocked_apps') ?? []).toSet();
    });
  }

  Future<void> _saveBlockedApps() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('blocked_apps', _blockedAppPackages.toList());
    await prefs.setString('blocked_apps_string', _blockedAppPackages.join(','));
  }

  Future<void> _loadApps() async {
    try {
      if (!kIsWeb && Platform.isAndroid) {
        List<AppInfo> apps = await InstalledApps.getInstalledApps(excludeSystemApps: true, withIcon: true);
        apps.sort((a, b) => a.name!.toLowerCase().compareTo(b.name!.toLowerCase()));
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Apps to Block'),
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
                    final packageName = app.packageName!;
                    final isBlocked = _blockedAppPackages.contains(packageName);
                    
                    return ListTile(
                      leading: app.icon != null
                          ? Image.memory(app.icon!, width: 40, height: 40)
                          : const Icon(Icons.android),
                      title: Text(app.name ?? 'Unknown App'),
                      subtitle: Text(packageName, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      trailing: Switch(
                        value: isBlocked,
                        activeColor: Theme.of(context).colorScheme.primary,
                        onChanged: (value) => _toggleAppBlock(packageName),
                      ),
                      onTap: () => _toggleAppBlock(packageName),
                    );
                  },
                ),
    );
  }
}
