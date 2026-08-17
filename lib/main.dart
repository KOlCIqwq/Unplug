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
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.system);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _loadSavedTheme();
  runApp(const DetoxApp());
}

Future<void> _loadSavedTheme() async {
  final prefs = await SharedPreferences.getInstance();
  final savedMode = prefs.getString('theme_mode') ?? 'system';
  if (savedMode == 'light') {
    themeNotifier.value = ThemeMode.light;
  } else if (savedMode == 'dark') {
    themeNotifier.value = ThemeMode.dark;
  } else {
    themeNotifier.value = ThemeMode.system;
  }
}

class DetoxApp extends StatelessWidget {
  const DetoxApp({super.key});

  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: const ColorScheme.light(
      primary: Color(0xFFF77E36),
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFFFDEC9),
      onPrimaryContainer: Color(0xFF3B1600),
      secondary: Color(0xFFE88746),
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFFFE8DC),
      onSecondaryContainer: Color(0xFF331A0B),
      surface: Color(0xFFFAF7F2),
      onSurface: Color(0xFF222124),
      surfaceContainerHighest: Color(0xFFF0E9DF),
      onSurfaceVariant: Color(0xFF5D5752),
      outline: Color(0xFF8A827B),
    ),
    scaffoldBackgroundColor: const Color(0xFFFAF7F2),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFFFAF7F2),
      foregroundColor: Color(0xFF222124),
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: const Color(0xFFF3EDE2),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: const Color(0xFFF3EDE2),
      indicatorColor: const Color(0xFFFFDEC9),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFF77E36));
        }
        return const TextStyle(fontSize: 12, color: Color(0xFF5D5752));
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: Color(0xFFF77E36));
        }
        return const IconThemeData(color: Color(0xFF5D5752));
      }),
    ),
  );

  static final ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFFFA8C42),
      onPrimary: Color(0xFF4C1E00),
      primaryContainer: Color(0xFF6C2E00),
      onPrimaryContainer: Color(0xFFFFDEC9),
      secondary: Color(0xFFE5BFA8),
      onSecondary: Color(0xFF432B1B),
      secondaryContainer: Color(0xFF5C4130),
      onSecondaryContainer: Color(0xFFFFDEC9),
      surface: Color(0xFF151417),
      onSurface: Color(0xFFEDE9E3),
      surfaceContainerHighest: Color(0xFF242228),
      onSurfaceVariant: Color(0xFFD6CDC4),
      outline: Color(0xFF9E948C),
    ),
    scaffoldBackgroundColor: const Color(0xFF151417),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF151417),
      foregroundColor: Color(0xFFEDE9E3),
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: const Color(0xFF211F25),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: const Color(0xFF1D1B21),
      indicatorColor: const Color(0xFF6C2E00),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFFA8C42));
        }
        return const TextStyle(fontSize: 12, color: Color(0xFFD6CDC4));
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: Color(0xFFFA8C42));
        }
        return const IconThemeData(color: Color(0xFFD6CDC4));
      }),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, currentThemeMode, _) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          title: 'Unplug Detox',
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: currentThemeMode,
          home: const MainNavigation(),
        );
      },
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
          _launchIntervention(
            args['package'] as String,
            args['debug'] as String?,
            args['isZenBlock'] as bool? ?? false,
            args['isLimitBlock'] as bool? ?? false,
            args['usedMinutes'] as int? ?? 0,
            args['limitMinutes'] as int? ?? 0,
          );
        } else if (args is String) {
          _launchIntervention(args, null, false, false, 0, 0);
        }
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      platform.invokeMethod('getPendingIntervention').then((args) {
        if (args != null && args is Map && args['package'] != null) {
          _launchIntervention(
            args['package'] as String,
            args['debug'] as String?,
            args['isZenBlock'] as bool? ?? false,
            args['isLimitBlock'] as bool? ?? false,
            args['usedMinutes'] as int? ?? 0,
            args['limitMinutes'] as int? ?? 0,
          );
        } else if (args != null && args is String) {
          _launchIntervention(args, null, false, false, 0, 0);
        }
      });
    });
  }

  Future<void> _launchIntervention(
    String packageName,
    String? debugInfo,
    bool isZenBlock,
    bool isLimitBlock,
    int usedMinutes,
    int limitMinutes,
  ) async {
    if (_isInterventionActive) return;
    _isInterventionActive = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final waitTime = (isZenBlock || isLimitBlock) ? 999999 : (prefs.getInt('wait_time_seconds') ?? 10);
      
      await Future.delayed(Duration.zero);

      final proceeded = await navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (context) => InterventionScreen(
            waitTimeSeconds: waitTime,
            targetAppName: packageName,
            debugInfo: debugInfo,
            isZenBlock: isZenBlock,
            isLimitBlock: isLimitBlock,
            usedMinutes: usedMinutes,
            limitMinutes: limitMinutes,
          ),
        ),
      );

      if (proceeded == false || proceeded == null) {
        await platform.invokeMethod('goHome');
      } else if (proceeded is int) {
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
