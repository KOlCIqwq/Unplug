import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _waitTimeSeconds = 10;
  bool _isLoading = true;

  final List<int> _waitOptions = [5, 10, 15, 30, 60];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _waitTimeSeconds = prefs.getInt('wait_time_seconds') ?? 10;
      _isLoading = false;
    });
  }

  Future<void> _updateWaitTime(int? newValue) async {
    if (newValue == null) return;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('wait_time_seconds', newValue);
    
    setState(() {
      _waitTimeSeconds = newValue;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        elevation: 0,
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                const Text(
                  'Intervention Wait Time',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'How long should you wait when opening a blocked app before you are allowed to proceed?',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                Card(
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: _waitTimeSeconds,
                        isExpanded: true,
                        icon: const Icon(Icons.timer),
                        items: _waitOptions.map((int value) {
                          return DropdownMenuItem<int>(
                            value: value,
                            child: Text('$value seconds'),
                          );
                        }).toList(),
                        onChanged: _updateWaitTime,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                const Text(
                  'Permissions',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'To detect when you open a blocked app, Doomscroll Detox requires Accessibility Service permission.',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    const platform = MethodChannel('com.example.detox_app/intervention');
                    platform.invokeMethod('openAccessibilitySettings');
                  },
                  icon: const Icon(Icons.settings_accessibility),
                  label: const Text('Open Accessibility Settings'),
                ),
              ],
            ),
    );
  }
}
