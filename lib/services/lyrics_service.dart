import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class LyricLine {
  final Duration timestamp;
  final String text;

  const LyricLine({
    required this.timestamp,
    required this.text,
  });

  @override
  String toString() => '[${timestamp.inSeconds}s]: $text';
}

class LyricsResult {
  final List<LyricLine> syncedLyrics;
  final String plainLyrics;
  final bool hasSynced;

  const LyricsResult({
    required this.syncedLyrics,
    required this.plainLyrics,
    required this.hasSynced,
  });

  static const empty = LyricsResult(
    syncedLyrics: [],
    plainLyrics: '',
    hasSynced: false,
  );
}

class LyricsService {
  LyricsService._();

  static final Map<String, LyricsResult> _cache = {};
  static const int _maxCacheSize = 60;

  static void invalidateCache(String title, String artist) {
    final cleanTitle = cleanString(title);
    final cleanArtist = cleanString(artist);
    final cacheKey = '${cleanTitle.toLowerCase()}___${cleanArtist.toLowerCase()}';
    _cache.remove(cacheKey);
  }

  static void clearCache() {
    _cache.clear();
  }

  static String cleanString(String input) {
    final cleaned = input
        .replaceAll(
          RegExp(
            r'\s*[\(\[](feat\.|ft\.|official|video|audio|remastered|lyric video|from|version|bonus|deluxe)[^\)\]]*[\)\]]',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(
          RegExp(
            r'\s*-\s*(feat\.|ft\.|official|video|audio|remastered|lyric video|remaster).*$',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
    return cleaned.isNotEmpty ? cleaned : input.trim();
  }

  /// Parses LRC text supporting multi-tag lines, global offsets, fractional seconds, and hours
  static List<LyricLine> parseLrc(String lrcText) {
    final lines = <LyricLine>[];
    Duration globalOffset = Duration.zero;

    // 1. Pre-scan for global offset tag across the entire document
    final offsetRegex = RegExp(r'\[offset:\s*([+-]?\d+)\s*\]', caseSensitive: false);
    final offsetMatch = offsetRegex.firstMatch(lrcText);
    if (offsetMatch != null) {
      final offsetMs = int.tryParse(offsetMatch.group(1) ?? '0') ?? 0;
      globalOffset = Duration(milliseconds: offsetMs);
    }

    // Matches timestamp prefix: [mm:ss], [mm:ss.xx], [mm:ss.xxx], [hh:mm:ss.xx]
    final prefixTimeTagRegex = RegExp(r'^(?:\[\s*(?:\d{1,3}:)?\d{1,3}:\d{2}(?:[:\.]\d{1,4})?\s*\])+');
    final individualTagRegex = RegExp(r'\[\s*(?:(\d{1,3}):)?(\d{1,3}):(\d{2})(?:[:\.](\d{1,4}))?\s*\]');

    for (final rawLine in lrcText.split('\n')) {
      final trimmed = rawLine.trim();
      if (trimmed.isEmpty) continue;

      // Check if line starts with timestamp tags
      final prefixMatch = prefixTimeTagRegex.firstMatch(trimmed);
      if (prefixMatch == null) continue; // Skip metadata tags like [ar:...], [ti:...]

      final prefixString = prefixMatch.group(0)!;
      // The rest of the line is the full lyric text (including any subsequent brackets)
      final lineText = trimmed.substring(prefixMatch.end).trim();

      final timeMatches = individualTagRegex.allMatches(prefixString);
      for (final match in timeMatches) {
        final hours = match.group(1) != null ? (int.tryParse(match.group(1)!) ?? 0) : 0;
        final mins = int.tryParse(match.group(2) ?? '0') ?? 0;
        final secs = int.tryParse(match.group(3) ?? '0') ?? 0;
        final frac = match.group(4) ?? '0';

        int millis = 0;
        if (frac.length == 1) {
          millis = (int.tryParse(frac) ?? 0) * 100;
        } else if (frac.length == 2) {
          millis = (int.tryParse(frac) ?? 0) * 10;
        } else if (frac.length >= 3) {
          millis = int.tryParse(frac.substring(0, 3)) ?? 0;
        }

        final ts = Duration(hours: hours, minutes: mins, seconds: secs, milliseconds: millis) + globalOffset;
        lines.add(LyricLine(
          timestamp: ts.isNegative ? Duration.zero : ts,
          text: lineText,
        ));
      }
    }

    lines.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return lines;
  }

  static void _cacheLyrics(String key, LyricsResult result) {
    if (_cache.length >= _maxCacheSize) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = result;
  }

  static Future<LyricsResult> fetchLyrics(
    String title,
    String artist, {
    bool forceRefresh = false,
  }) async {
    final cleanTitle = cleanString(title);
    final cleanArtist = cleanString(artist);
    final cacheKey = '${cleanTitle.toLowerCase()}___${cleanArtist.toLowerCase()}';

    if (!forceRefresh && _cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!;
    }

    const headers = {
      'User-Agent': 'PulsePipe/1.0 (https://github.com/taezeem14/PulsePipe)',
      'Accept': 'application/json',
    };

    // 1. Direct match by track and artist
    try {
      final getUrl = Uri.https('lrclib.net', '/api/get', {
        'track_name': cleanTitle,
        'artist_name': cleanArtist,
      });
      final resp = await http.get(getUrl, headers: headers).timeout(const Duration(seconds: 4));

      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map) {
          final data = Map<String, dynamic>.from(decoded);
          final syncedStr = data['syncedLyrics'] as String?;
          final plainStr = data['plainLyrics'] as String? ?? '';

          final syncedLines = syncedStr != null ? parseLrc(syncedStr) : <LyricLine>[];
          if (syncedLines.isNotEmpty || plainStr.trim().isNotEmpty) {
            final result = LyricsResult(
              syncedLyrics: syncedLines,
              plainLyrics: plainStr.isNotEmpty ? plainStr : syncedLines.map((l) => l.text).join('\n'),
              hasSynced: syncedLines.isNotEmpty,
            );
            _cacheLyrics(cacheKey, result);
            return result;
          }
        }
      } else if (resp.statusCode == 429) {
        debugPrint('[LyricsService] LRCLib rate limit on /api/get');
        return LyricsResult.empty;
      }
    } catch (e) {
      debugPrint('[LyricsService] Direct match error: $e');
    }

    // 2. Search fallback
    try {
      final queryParam = '$cleanTitle $cleanArtist'.trim();
      final searchUrl = Uri.https('lrclib.net', '/api/search', {
        'q': queryParam,
      });
      final searchResp = await http.get(searchUrl, headers: headers).timeout(const Duration(seconds: 5));

      if (searchResp.statusCode == 200) {
        final decodedList = jsonDecode(searchResp.body);
        if (decodedList is List && decodedList.isNotEmpty) {
          for (final rawItem in decodedList) {
            if (rawItem is! Map) continue;
            final item = Map<String, dynamic>.from(rawItem);
            final syncedStr = item['syncedLyrics'] as String?;
            final plainStr = item['plainLyrics'] as String? ?? '';
            final syncedLines = syncedStr != null ? parseLrc(syncedStr) : <LyricLine>[];

            if (syncedLines.isNotEmpty || plainStr.trim().isNotEmpty) {
              final result = LyricsResult(
                syncedLyrics: syncedLines,
                plainLyrics: plainStr.isNotEmpty ? plainStr : syncedLines.map((l) => l.text).join('\n'),
                hasSynced: syncedLines.isNotEmpty,
              );
              _cacheLyrics(cacheKey, result);
              return result;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[LyricsService] Search fallback error: $e');
    }

    return LyricsResult.empty;
  }
}
