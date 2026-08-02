import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:installed_apps/installed_apps.dart';
import 'screens/dashboard_screen.dart';
import 'screens/intervention_screen.dart';
import 'screens/app_selector_screen.dart';
import 'screens/settings_screen.dart';


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
  }

  void _setupMethodChannel() {
    platform.setMethodCallHandler((call) async {
      if (call.method == "triggerIntervention") {
        final args = call.arguments;
        if (args is Map) {
          _launchIntervention(args['package'] as String, args['debug'] as String?);
        } else if (args is String) {
          _launchIntervention(args, null);
        }
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      platform.invokeMethod('getPendingIntervention').then((args) {
        if (args != null && args is Map && args['package'] != null) {
          _launchIntervention(args['package'] as String, args['debug'] as String?);
        } else if (args != null && args is String) {
          _launchIntervention(args, null);
        }
      });
    });
  }

  Future<void> _launchIntervention(String packageName, String? debugInfo) async {
    if (_isInterventionActive) return;
    _isInterventionActive = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final waitTime = prefs.getInt('wait_time_seconds') ?? 10;
      
      await Future.delayed(Duration.zero);

      final proceeded = await navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (context) => InterventionScreen(
            waitTimeSeconds: waitTime,
            targetAppName: packageName,
            debugInfo: debugInfo,
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

