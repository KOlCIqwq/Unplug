import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import '../main.dart';
import '../services/dnd_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  int _waitTimeSeconds = 10;
  String _themeModeString = 'system';
  bool _showQuotes = true;
  bool _isLoading = true;
  bool _silenceInZen = false;

  final List<int> _waitOptions = [5, 10, 15, 30, 60];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final silence = await DndService.loadPreference();
    setState(() {
      _waitTimeSeconds = prefs.getInt('wait_time_seconds') ?? 10;
      _themeModeString = prefs.getString('theme_mode') ?? 'system';
      _showQuotes = prefs.getBool('show_quotes') ?? true;
      _silenceInZen = silence;
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

  Future<void> _updateThemeMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', mode);

    setState(() {
      _themeModeString = mode;
    });

    if (mode == 'light') {
      themeNotifier.value = ThemeMode.light;
    } else if (mode == 'dark') {
      themeNotifier.value = ThemeMode.dark;
    } else {
      themeNotifier.value = ThemeMode.system;
    }
  }

  Future<void> _toggleShowQuotes(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('show_quotes', value);
    setState(() {
      _showQuotes = value;
    });
  }

  Future<void> _toggleSilenceInZen(bool value) async {
    if (value) {
      final granted = await DndService.isDndPermissionGranted();
      if (!granted && mounted) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.do_not_disturb_on_rounded, color: Color(0xFFF77E36)),
                SizedBox(width: 8),
                Text('Do Not Disturb Access'),
              ],
            ),
            content: const Text(
              'To silence notifications and phone calls when Zen Space is active, Android requires Do Not Disturb access permission.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
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
        if (proceed != true) return;
      }
    }
    await DndService.setSilenceEnabled(value);
    setState(() {
      _silenceInZen = value;
    });
  }

  Widget _buildThemeTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required String modeKey,
    required ColorScheme colorScheme,
  }) {
    final isSelected = _themeModeString == modeKey;
    return InkWell(
      onTap: () => _updateThemeMode(modeKey),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
              size: 24,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        elevation: 0,
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20.0),
              children: [
                // Appearance / Theme Section
                Text(
                  'Appearance',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Choose your preferred visual theme.',
                  style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
                ),
                const SizedBox(height: 14),
                Card(
                  color: colorScheme.surfaceContainerHighest,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                    child: Column(
                      children: [
                        _buildThemeTile(
                          title: 'Light Mode',
                          subtitle: 'Warm Cream & Coral (matches logo)',
                          icon: Icons.wb_sunny_rounded,
                          modeKey: 'light',
                          colorScheme: colorScheme,
                        ),
                        Divider(height: 1, indent: 48, color: colorScheme.outline.withValues(alpha: 0.15)),
                        _buildThemeTile(
                          title: 'Dark Mode',
                          subtitle: 'Deep Slate & Radiant Coral',
                          icon: Icons.nightlight_round,
                          modeKey: 'dark',
                          colorScheme: colorScheme,
                        ),
                        Divider(height: 1, indent: 48, color: colorScheme.outline.withValues(alpha: 0.15)),
                        _buildThemeTile(
                          title: 'System Default',
                          subtitle: 'Follows your device system theme',
                          icon: Icons.phone_android_rounded,
                          modeKey: 'system',
                          colorScheme: colorScheme,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 28),

                // Mindfulness & Quotes Section
                Text(
                  'Mindfulness & Prompts',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Customize the content shown during the pause countdown.',
                  style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
                ),
                const SizedBox(height: 14),
                Card(
                  color: colorScheme.surfaceContainerHighest,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: SwitchListTile(
                    title: const Text('Show Mindfulness Quotes', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text(
                      'Display inspirational quotes and mindfulness reflections on the intervention screen',
                      style: TextStyle(fontSize: 12),
                    ),
                    secondary: Icon(Icons.format_quote_rounded, color: colorScheme.primary),
                    value: _showQuotes,
                    activeTrackColor: colorScheme.primary,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
                    onChanged: _toggleShowQuotes,
                  ),
                ),

                const SizedBox(height: 28),

                // Zen Space Silence & Do Not Disturb Section
                Text(
                  'Zen Space Silence & Focus',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Silence your phone while concentrating in Zen Space.',
                  style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
                ),
                const SizedBox(height: 14),
                Card(
                  color: colorScheme.surfaceContainerHighest,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: SwitchListTile(
                    title: const Text('Silence Phone in Zen Space', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text(
                      'Activates Do Not Disturb / Silent mode during Zen Space and automatically restores previous sound settings when it finishes',
                      style: TextStyle(fontSize: 12),
                    ),
                    secondary: Icon(Icons.do_not_disturb_on_rounded, color: colorScheme.primary),
                    value: _silenceInZen,
                    activeTrackColor: colorScheme.primary,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
                    onChanged: _toggleSilenceInZen,
                  ),
                ),

                const SizedBox(height: 28),

                // Intervention Wait Time Section
                Text(
                  'Intervention Wait Time',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'How long should you pause when opening a blocked app before you are allowed to proceed?',
                  style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
                ),
                const SizedBox(height: 14),
                Card(
                  color: colorScheme.surfaceContainerHighest,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: _waitTimeSeconds,
                        isExpanded: true,
                        icon: const Icon(Icons.timer_outlined),
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

                const SizedBox(height: 28),

                // Permissions Section
                Text(
                  'Permissions',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'To detect when you open a blocked app, Unplug requires Accessibility Service permission.',
                  style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
                ),
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  onPressed: () {
                    const platform = MethodChannel('com.example.detox_app/intervention');
                    platform.invokeMethod('openAccessibilitySettings');
                  },
                  icon: const Icon(Icons.settings_accessibility),
                  label: const Text('Open Accessibility Settings'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    DndService.openDndSettings();
                  },
                  icon: const Icon(Icons.do_not_disturb_on_outlined),
                  label: const Text('Do Not Disturb Access Settings'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
    );
  }
}
