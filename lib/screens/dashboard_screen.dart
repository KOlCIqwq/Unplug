import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadStats();
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

  Future<void> _loadStats() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _cancelCount = prefs.getInt('cancel_count') ?? 0;
      _zenModeEndTime = prefs.getInt('zen_mode_end_time') ?? 0;
      _isLoading = false;
    });

    _zenTimer?.cancel();
    _zenTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_zenModeEndTime > 0 && DateTime.now().millisecondsSinceEpoch > _zenModeEndTime) {
        setState(() {
          _zenModeEndTime = 0;
        });
      } else if (_zenModeEndTime > 0) {
        setState(() {}); // trigger rebuild to update time
      }
    });
  }

  Future<void> _incrementCancelCount() async {
    final prefs = await SharedPreferences.getInstance();
    int newCount = _cancelCount + 1;
    await prefs.setInt('cancel_count', newCount);
    setState(() {
      _cancelCount = newCount;
    });
  }

  Future<void> _enterZenSpace(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    final endTime = DateTime.now().millisecondsSinceEpoch + (minutes * 60 * 1000);
    await prefs.setInt('zen_mode_end_time', endTime);
    setState(() {
      _zenModeEndTime = endTime;
    });
  }

  Future<void> _exitZenSpace() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('zen_mode_end_time', 0);
    setState(() {
      _zenModeEndTime = 0;
    });
  }

  String _formatTime(DateTime time) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return '${twoDigits(time.hour)}:${twoDigits(time.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Rough estimation: each cancel saves ~5 mins of doomscrolling
    final int estimatedMinutesSaved = _cancelCount * 5; 

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.shield_moon, size: 80, color: Colors.teal),
              const SizedBox(height: 20),
              Text(
              '$_cancelCount',
              style: Theme.of(context).textTheme.displayLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const Text(
              'Times you resisted the urge',
              style: TextStyle(fontSize: 18, color: Colors.white70),
            ),
            const SizedBox(height: 40),
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              margin: const EdgeInsets.symmetric(horizontal: 32),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    const Text('Estimated Time Saved', style: TextStyle(fontSize: 16)),
                    const SizedBox(height: 8),
                    Text(
                      '$estimatedMinutesSaved mins',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 40),
            if (_zenModeEndTime > DateTime.now().millisecondsSinceEpoch)
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                margin: const EdgeInsets.symmetric(horizontal: 32),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      const Icon(Icons.self_improvement, size: 48),
                      const SizedBox(height: 8),
                      const Text('Zen Space Active', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text(
                        'Ends at ${_formatTime(DateTime.fromMillisecondsSinceEpoch(_zenModeEndTime))}',
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 16),
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
                margin: const EdgeInsets.symmetric(horizontal: 32),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      const Icon(Icons.self_improvement, size: 48),
                      const SizedBox(height: 8),
                      const Text('Enter Zen Space', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      const Text(
                        'Block all apps except the Zen Whitelist.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        children: [15, 30, 60, 120].map((mins) {
                          final isSelected = _selectedZenMinutes == mins;
                          return ChoiceChip(
                            label: Text(mins >= 60 ? '${mins ~/ 60}h' : '${mins}m'),
                            selected: isSelected,
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
            const SizedBox(height: 40),
            TextButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: const Text('Test Intervention Screen'),
              onPressed: () async {
                // Refresh wait time before launching in case it was changed in Settings
                final prefs = await SharedPreferences.getInstance();
                final currentWaitTime = prefs.getInt('wait_time_seconds') ?? 10;
                if (!context.mounted) return;

                final dynamic proceeded = await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => InterventionScreen(
                      waitTimeSeconds: currentWaitTime,
                      targetAppName: 'Instagram (Test)',
                    ),
                  ),
                );

                // In intervention_screen.dart, we pop(false) if user hits Cancel, pop(true) if Continue.
                // We increment the count if they cancelled (didn't proceed).
                if (proceeded == false) {
                  _incrementCancelCount();
                }
              },
            ),
          ],
        ),
      ),
    ),
  );
}
}
