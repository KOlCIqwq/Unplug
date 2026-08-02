import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'intervention_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with WidgetsBindingObserver {
  int _cancelCount = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadStats();
  }

  @override
  void dispose() {
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
      _isLoading = false;
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
              color: Theme.of(context).colorScheme.surfaceVariant,
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
            const SizedBox(height: 60),
            ElevatedButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: const Text('Test Intervention Screen'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              onPressed: () async {
                // Refresh wait time before launching in case it was changed in Settings
                final prefs = await SharedPreferences.getInstance();
                final currentWaitTime = prefs.getInt('wait_time_seconds') ?? 10;

                final bool? proceeded = await Navigator.of(context).push(
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
    );
  }
}
