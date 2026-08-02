import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PromptService {
  static const String _cachedQuotesKey = 'cached_api_quotes';

  static final List<String> _actionOrientedPrompts = [
    '“It is not that we have a short time to live, but that we waste a lot of it.”\n— Seneca',
    '“Lost time is never found again.”\n— Benjamin Franklin',
    '“Discipline is choosing between what you want now and what you want most.”\n— Abraham Lincoln',
    '“You have power over your mind - not outside events. Realize this, and you will find strength.”\n— Marcus Aurelius',
    '“How long are you going to wait before you demand the best for yourself?”\n— Epictetus',
    '“No person has the power to have everything they want, but it is in their power not to want what they have not.”\n— Seneca',
    '“Concentrate every minute like a Roman on doing what’s in front of you with precise and genuine seriousness.”\n— Marcus Aurelius',
    '“Don’t trade your long-term goals for cheap dopamine.”',
    '“You could be building something great right now.”',
    '“Close the screen. Go read, create, or exercise.”',
    '“Action cures anxiety. Put down the phone and start.”',
    '“What project did you put on hold to open this app?”',
    '“Are you consuming someone else’s life instead of building yours?”',
    '“Your future self is shaped by what you do in the next 10 minutes.”',
    '“Turn your scroll time into skill time.”',
    '“You don’t need more time, you need more focus.”',
    '“The phone is a tool for your life, not a substitute for living it.”',
    '“Go drink some water, stretch, or make progress on your goal.”',
    '“The cost of procrastination is the life you could have lived.”',
    '“Silence the distractions. Reclaim your ambition.”',
  ];

  static final Random _random = Random();

  /// Gets a prompt immediately prioritizing cached API quotes
  static Future<String> getInitialPrompt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getStringList(_cachedQuotesKey) ?? [];
      if (cached.isNotEmpty) {
        final quote = cached.removeAt(_random.nextInt(cached.length));
        await prefs.setStringList(_cachedQuotesKey, cached);
        // Trigger background replenish
        fetchAndCacheQuotes();
        return quote;
      }
    } catch (e) {
      debugPrint('Error loading cached quote: $e');
    }
    return getRandomPrompt();
  }

  static String getRandomPrompt() {
    return _actionOrientedPrompts[_random.nextInt(_actionOrientedPrompts.length)];
  }

  /// Actively fetches from targeted online APIs with priority on Stoic/Discipline sources
  static Future<String?> fetchMindfulPrompt() async {
    // 1. Try Stoic Quotes API
    try {
      final quote = await _fetchFromStoicQuotes();
      if (quote != null) {
        _cacheQuote(quote);
        return quote;
      }
    } catch (e) {
      debugPrint('StoicQuotes API failed: $e');
    }

    // 2. Try Quotable with motivational/wisdom tags
    try {
      final quote = await _fetchFromQuotable();
      if (quote != null) {
        _cacheQuote(quote);
        return quote;
      }
    } catch (e) {
      debugPrint('Quotable API failed: $e');
    }

    // 3. Try ZenQuotes API
    try {
      final quote = await _fetchFromZenQuotes();
      if (quote != null) {
        _cacheQuote(quote);
        return quote;
      }
    } catch (e) {
      debugPrint('ZenQuotes API failed: $e');
    }

    return null;
  }

  /// Background job to replenish cached quotes
  static void fetchAndCacheQuotes() {
    fetchMindfulPrompt();
  }

  static Future<void> _cacheQuote(String quote) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getStringList(_cachedQuotesKey) ?? [];
      if (!cached.contains(quote)) {
        cached.add(quote);
        if (cached.length > 20) {
          cached.removeAt(0);
        }
        await prefs.setStringList(_cachedQuotesKey, cached);
      }
    } catch (_) {}
  }

  static Future<String?> _fetchFromStoicQuotes() async {
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
        if (text.isNotEmpty && text.length <= 150) {
          final res = author != null && author.isNotEmpty ? '“$text”\n— $author' : '“$text”';
          debugPrint('[PromptService] Fetched from StoicQuotes: $res');
          return res;
        }
      }
    }
    return null;
  }

  static Future<String?> _fetchFromQuotable() async {
    final client = HttpClient();
    client.badCertificateCallback = (cert, host, port) => true;
    client.connectionTimeout = const Duration(seconds: 3);
    final request = await client.getUrl(Uri.parse('https://api.quotable.io/random?tags=motivational,inspirational,wisdom'));
    request.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0 (Linux; Android 10)');
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    
    final response = await request.close().timeout(const Duration(seconds: 3));
    if (response.statusCode == 200) {
      final body = await response.transform(utf8.decoder).join();
      final data = jsonDecode(body);
      String? content;
      String? author;
      if (data is List && data.isNotEmpty) {
        content = (data[0]['content'] as String?)?.trim();
        author = (data[0]['author'] as String?)?.trim();
      } else if (data is Map) {
        content = (data['content'] as String?)?.trim();
        author = (data['author'] as String?)?.trim();
      }
      if (content != null && content.isNotEmpty && content.length <= 150) {
        final res = author != null && author.isNotEmpty ? '“$content”\n— $author' : '“$content”';
        debugPrint('[PromptService] Fetched from Quotable: $res');
        return res;
      }
    }
    return null;
  }

  static Future<String?> _fetchFromZenQuotes() async {
    final client = HttpClient();
    client.badCertificateCallback = (cert, host, port) => true;
    client.connectionTimeout = const Duration(seconds: 3);
    final request = await client.getUrl(Uri.parse('https://zenquotes.io/api/random'));
    request.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0 (Linux; Android 10)');
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    
    final response = await request.close().timeout(const Duration(seconds: 3));
    if (response.statusCode == 200) {
      final body = await response.transform(utf8.decoder).join();
      final data = jsonDecode(body);
      if (data is List && data.isNotEmpty) {
        final item = data[0];
        final q = (item['q'] as String?)?.trim();
        final a = (item['a'] as String?)?.trim();
        if (q != null && q.isNotEmpty && q.length <= 150) {
          final res = a != null && a.isNotEmpty ? '“$q”\n— $a' : '“$q”';
          debugPrint('[PromptService] Fetched from ZenQuotes: $res');
          return res;
        }
      }
    }
    return null;
  }
}
