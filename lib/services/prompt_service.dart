import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PromptService {
  static const String _dailyQuotesKey = 'daily_shuffled_quotes';
  static const String _lastFetchDateKey = 'last_quote_fetch_date';
  static const int _maxQuoteLength = 85;

  // Short, punchy, curated action-oriented quotes (< 85 chars) for immediate offline availability
  static final List<String> _curatedShortPrompts = [
    '“Lost time is never found again.”\n— Benjamin Franklin',
    '“We waste a lot of the short time we have to live.”\n— Seneca',
    'Don’t trade your long-term goals for cheap dopamine.',
    'You could be building something great right now.',
    'Close the screen. Go read, create, or exercise.',
    'Action cures anxiety. Put down the phone and start.',
    'What project did you put on hold to open this app?',
    'Are you consuming someone else’s life instead of building yours?',
    'Your future self is shaped by what you do right now.',
    'Turn your scroll time into skill time.',
    '“You don’t need more time, you need more focus.”',
    'The phone is a tool for your life, not a substitute for living.',
    'Go drink some water, stretch, or work on your goal.',
    '“The cost of procrastination is the life you could have lived.”',
    'Silence the distractions. Reclaim your ambition.',
    '“Discipline is choosing between what you want now and most.”\n— A. Lincoln',
    '“Demand the best for yourself.”\n— Epictetus',
  ];

  static final Random _random = Random();

  /// Gets a quote immediately from the daily shuffled pool or curated list
  static Future<String> getNextQuote() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dailyQuotes = prefs.getStringList(_dailyQuotesKey) ?? [];
      
      if (dailyQuotes.isNotEmpty) {
        // Pick and cycle
        final quote = dailyQuotes.removeAt(0);
        await prefs.setStringList(_dailyQuotesKey, dailyQuotes);
        
        // If pool is running low, schedule fetch
        if (dailyQuotes.length < 5) {
          checkAndFetchDailyQuotes(force: true);
        }
        return quote;
      }
    } catch (e) {
      debugPrint('[PromptService] Error getting next quote: $e');
    }

    return getRandomCuratedPrompt();
  }

  /// Synchronous fallback
  static String getRandomCuratedPrompt() {
    return _curatedShortPrompts[_random.nextInt(_curatedShortPrompts.length)];
  }

  /// Checks if daily quotes need to be fetched (once per day or if empty)
  static Future<void> checkAndFetchDailyQuotes({bool force = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final todayStr = DateTime.now().toIso8601String().substring(0, 10);
      final lastDate = prefs.getString(_lastFetchDateKey);
      final currentQuotes = prefs.getStringList(_dailyQuotesKey) ?? [];

      if (!force && lastDate == todayStr && currentQuotes.length >= 10) {
        debugPrint('[PromptService] Daily quotes already up-to-date for $todayStr (${currentQuotes.length} cached)');
        return;
      }

      debugPrint('[PromptService] Fetching fresh daily quotes batch...');
      final List<String> fetchedPool = [];

      // 1. Fetch batch from ZenQuotes (50 quotes in one API call)
      final zenQuotes = await _fetchZenQuotesBatch();
      fetchedPool.addAll(zenQuotes);

      // 2. Fetch from Stoic Quotes
      final stoicQuote = await _fetchStoicQuote();
      if (stoicQuote != null) fetchedPool.add(stoicQuote);

      // 3. Fetch from Quotable
      final quotable = await _fetchQuotableQuotes();
      fetchedPool.addAll(quotable);

      // Filter: length <= _maxQuoteLength, clean text, and remove duplicates
      final Set<String> filteredSet = {};
      for (final q in fetchedPool) {
        final clean = q.trim();
        // Check main body length without author attribution
        final bodyOnly = clean.split('\n—').first.replaceAll('“', '').replaceAll('”', '').trim();
        if (bodyOnly.length <= _maxQuoteLength && bodyOnly.length >= 15) {
          filteredSet.add(clean);
        }
      }

      if (filteredSet.isNotEmpty) {
        final List<String> combined = [...currentQuotes, ...filteredSet].toSet().toList();
        combined.shuffle(_random);
        await prefs.setStringList(_dailyQuotesKey, combined);
        await prefs.setString(_lastFetchDateKey, todayStr);
        debugPrint('[PromptService] Successfully updated daily quote pool: ${combined.length} quotes cached.');
      }
    } catch (e) {
      debugPrint('[PromptService] Error in checkAndFetchDailyQuotes: $e');
    }
  }

  static Future<List<String>> _fetchZenQuotesBatch() async {
    final List<String> result = [];
    try {
      final client = HttpClient();
      client.badCertificateCallback = (cert, host, port) => true;
      client.connectionTimeout = const Duration(seconds: 4);

      final request = await client.getUrl(Uri.parse('https://zenquotes.io/api/quotes'));
      request.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0 (Linux; Android 10)');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');

      final response = await request.close().timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body);
        if (data is List) {
          for (final item in data) {
            final q = (item['q'] as String?)?.trim();
            final a = (item['a'] as String?)?.trim();
            if (q != null && q.isNotEmpty) {
              final formatted = a != null && a.isNotEmpty ? '“$q”\n— $a' : '“$q”';
              result.add(formatted);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[PromptService] ZenQuotes batch fetch failed: $e');
    }
    return result;
  }

  static Future<String?> _fetchStoicQuote() async {
    try {
      final client = HttpClient();
      client.badCertificateCallback = (cert, host, port) => true;
      client.connectionTimeout = const Duration(seconds: 3);

      final request = await client.getUrl(Uri.parse('https://stoic-quotes.com/api/quote'));
      request.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0 (Linux; Android 10)');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');

      final response = await request.close().timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body);
        if (data is Map && data['text'] != null) {
          final text = (data['text'] as String).trim();
          final author = (data['author'] as String?)?.trim();
          if (text.isNotEmpty) {
            return author != null && author.isNotEmpty ? '“$text”\n— $author' : '“$text”';
          }
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<List<String>> _fetchQuotableQuotes() async {
    final List<String> result = [];
    try {
      final client = HttpClient();
      client.badCertificateCallback = (cert, host, port) => true;
      client.connectionTimeout = const Duration(seconds: 3);

      final request = await client.getUrl(Uri.parse('https://api.quotable.io/quotes/random?limit=10&tags=motivational,wisdom,inspirational'));
      request.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0 (Linux; Android 10)');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');

      final response = await request.close().timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body);
        if (data is List) {
          for (final item in data) {
            final content = (item['content'] as String?)?.trim();
            final author = (item['author'] as String?)?.trim();
            if (content != null && content.isNotEmpty) {
              result.add(author != null && author.isNotEmpty ? '“$content”\n— $author' : '“$content”');
            }
          }
        }
      }
    } catch (_) {}
    return result;
  }
}
