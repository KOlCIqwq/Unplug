import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/dashboard_screen.dart';
import 'screens/intervention_screen.dart';
import 'screens/app_selector_screen.dart';
import 'screens/zen_apps_screen.dart';
import 'screens/settings_screen.dart';
import 'services/prompt_service.dart';


final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  runApp(const DetoxApp());
}

class DetoxApp extends StatelessWidget {
  const DetoxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Doomscroll Detox',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const MainNavigation(),
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _selectedIndex = 0;
  static const platform = MethodChannel('com.example.detox_app/intervention');

  bool _isInterventionActive = false;

  @override
  void initState() {
    super.initState();
    _setupMethodChannel();
    PromptService.checkAndFetchDailyQuotes();
  }

  void _setupMethodChannel() {
    platform.setMethodCallHandler((call) async {
      if (call.method == "triggerIntervention") {
        final args = call.arguments;
        if (args is Map) {
          _launchIntervention(args['package'] as String, args['debug'] as String?, args['isZenBlock'] as bool? ?? false);
        } else if (args is String) {
          _launchIntervention(args, null, false);
        }
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      platform.invokeMethod('getPendingIntervention').then((args) {
        if (args != null && args is Map && args['package'] != null) {
          _launchIntervention(args['package'] as String, args['debug'] as String?, args['isZenBlock'] as bool? ?? false);
        } else if (args != null && args is String) {
          _launchIntervention(args, null, false);
        }
      });
    });
  }

  Future<void> _launchIntervention(String packageName, String? debugInfo, bool isZenBlock) async {
    if (_isInterventionActive) return;
    _isInterventionActive = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final waitTime = isZenBlock ? 999999 : (prefs.getInt('wait_time_seconds') ?? 10);
      
      await Future.delayed(Duration.zero);

      final proceeded = await navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (context) => InterventionScreen(
            waitTimeSeconds: waitTime,
            targetAppName: packageName,
            debugInfo: debugInfo,
            isZenBlock: isZenBlock,
          ),
        ),
      );

      if (proceeded == false || proceeded == null) {
        await platform.invokeMethod('goHome'); // Kick them back to the home screen
      } else if (proceeded is int) {
        // Native side will whitelist it for the chosen minutes, decrement the optimistic resist counter, and launch it
        await platform.invokeMethod('allowAppTemporarily', {
          'package': packageName,
          'durationMinutes': proceeded,
        });
      } else if (proceeded == true) {
        await platform.invokeMethod('allowAppTemporarily', {
          'package': packageName,
          'durationMinutes': 5,
        });
      }
    } finally {
      _isInterventionActive = false;
    }
  }

  static const List<Widget> _screens = <Widget>[
    DashboardScreen(),
    AppSelectorScreen(),
    ZenAppsScreen(),
    SettingsScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: _screens.elementAt(_selectedIndex),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onItemTapped,
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Stats',
          ),
          NavigationDestination(
            icon: Icon(Icons.apps_outlined),
            selectedIcon: Icon(Icons.apps),
            label: 'Blocked Apps',
          ),
          NavigationDestination(
            icon: Icon(Icons.self_improvement_outlined),
            selectedIcon: Icon(Icons.self_improvement),
            label: 'Zen Apps',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

// Stubs for the screens

