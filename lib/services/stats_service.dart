import 'package:shared_preferences/shared_preferences.dart';

class StatsService {
  /// Returns the mean/average session duration in minutes for a given package.
  /// If no usage has been recorded yet, defaults to 8 minutes as a sensible baseline.
  static Future<int> getMeanSessionMinutes(String packageName) async {
    final prefs = await SharedPreferences.getInstance();
    final int totalMs = prefs.getInt('total_session_ms_$packageName') ?? 0;
    final int sessionCount = prefs.getInt('sessions_count_$packageName') ?? 0;

    if (sessionCount > 0 && totalMs > 0) {
      final int avgMins = ((totalMs / sessionCount) / (60 * 1000)).round();
      return avgMins > 0 ? avgMins : 1;
    }
    return 8; // Default baseline session duration in minutes
  }

  /// Records a resisted urge when the user cancels or closes an intervention for [packageName].
  /// Accurately adds the specific app's mean session time to the saved time counter.
  static Future<int> recordResist(String packageName) async {
    final prefs = await SharedPreferences.getInstance();
    final int meanSavedMinutes = await getMeanSessionMinutes(packageName);

    final int currentCancelCount = prefs.getInt('cancel_count') ?? 0;
    final int currentSavedMinutes = prefs.getInt('total_saved_minutes') ?? 0;
    final int appResists = prefs.getInt('resists_$packageName') ?? 0;
    final int appSavedMinutes = prefs.getInt('saved_minutes_$packageName') ?? 0;

    await prefs.setInt('cancel_count', currentCancelCount + 1);
    await prefs.setInt('total_saved_minutes', currentSavedMinutes + meanSavedMinutes);
    await prefs.setInt('resists_$packageName', appResists + 1);
    await prefs.setInt('saved_minutes_$packageName', appSavedMinutes + meanSavedMinutes);

    return meanSavedMinutes;
  }

  /// Helper to record session data directly from Flutter (e.g. for testing)
  static Future<void> recordSession(String packageName, int elapsedMs) async {
    if (elapsedMs <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final dateKey = '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';

    // Daily usage
    final int currentDailyMs = prefs.getInt('usage_${dateKey}_$packageName') ?? 0;
    await prefs.setInt('usage_${dateKey}_$packageName', currentDailyMs + elapsedMs);

    // All-time session tracking
    final int totalMs = prefs.getInt('total_session_ms_$packageName') ?? 0;
    final int count = prefs.getInt('sessions_count_$packageName') ?? 0;

    await prefs.setInt('total_session_ms_$packageName', totalMs + elapsedMs);
    if (elapsedMs >= 15000 || count == 0) {
      await prefs.setInt('sessions_count_$packageName', count + 1);
    }
  }
}
