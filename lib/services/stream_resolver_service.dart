import 'package:flutter/foundation.dart';
import '../models/song.dart';
import 'youtube_importer_service.dart';
class StreamResolverService {
  static const int _maxCacheEntries = 100;
  static final Map<String, ({List<String> streams, DateTime cachedAt})> _resolvedCache = {};

  static void _cacheStreams(String key, List<String> streams) {
    if (_resolvedCache.length >= _maxCacheEntries) {
      _resolvedCache.remove(_resolvedCache.keys.first);
    }
    _resolvedCache[key] = (streams: streams, cachedAt: DateTime.now());
  }

  /// Invalidate cached stream candidates for a song if playback fails
  static void invalidateCache(String key) {
    _resolvedCache.remove(key);
  }

  static final Set<String> _currentlyPreloading = {};

  /// Checks if a song has already been pre-resolved into memory cache
  static bool isPreloaded(Song song) {
    final cacheKey = song.id.isNotEmpty ? song.id : song.streamUrl;
    final cached = _resolvedCache[cacheKey];
    return cached != null && cached.streams.isNotEmpty && DateTime.now().difference(cached.cachedAt).inHours < 4;
  }

  /// Prefetch playable audio stream for a track in the background
  static void prefetchPlayableStreams(Song song) {
    if (isPreloaded(song) || _currentlyPreloading.contains(song.id)) return;
    _currentlyPreloading.add(song.id);
    resolvePlayableStreamCandidates(song).catchError((e) {
      debugPrint('[StreamResolverService] Prefetch background error for "${song.title}": $e');
      return <String>[];
    }).whenComplete(() {
      _currentlyPreloading.remove(song.id);
    });
  }

  /// Proactively preloads an entire list of songs in parallel background batches
  /// (e.g. all songs in a playlist, top trending, or search results)
  static void preloadSongs(List<Song> songs, {int maxCount = 15}) {
    final targets = songs.take(maxCount).where((s) => !isPreloaded(s) && !_currentlyPreloading.contains(s.id)).toList();
    if (targets.isEmpty) return;

    Future.microtask(() async {
      // Process in concurrent batches of 3 to resolve quickly without network choking
      const batchSize = 3;
      for (int i = 0; i < targets.length; i += batchSize) {
        final end = (i + batchSize < targets.length) ? i + batchSize : targets.length;
        final batch = targets.sublist(i, end);
        for (final s in batch) {
          _currentlyPreloading.add(s.id);
        }
        await Future.wait(
          batch.map((song) async {
            try {
              await resolvePlayableStreamCandidates(song);
            } catch (e) {
              debugPrint('[StreamResolverService] Batch preload error for "${song.title}": $e');
            } finally {
              _currentlyPreloading.remove(song.id);
            }
          }),
        );
      }
    });
  }

  /// Normalizes title string by stripping noise words
  static String cleanTitle(String raw) {
    return raw
        .replaceAll(
          RegExp(
            r'\((?:official|music|video|audio|lyrics|hd|4k|visualizer|remastered|lyric|prod\.|feat\.|ft\.).*?\)',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(
          RegExp(
            r'\[(?:official|music|video|audio|lyrics|hd|4k|visualizer|remastered|lyric|prod\.|feat\.|ft\.).*?\]',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r'[\-_|]', caseSensitive: false), ' ')
        .trim();
  }

  /// Pure NewPipe YouTube Stream Resolver:
  /// 1. Offline local audio files
  /// 2. Direct YouTube video audio extraction via YoutubeExplode (requireWatchPage: false)
  /// 3. Piped REST audio proxy failover
  /// 4. Dynamic YouTube search & stream extraction if only title/artist is known
  static Future<List<String>> resolvePlayableStreamCandidates(Song song) async {
    final cacheKey = song.id.isNotEmpty ? song.id : song.streamUrl;
    final cached = _resolvedCache[cacheKey];
    if (cached != null && cached.streams.isNotEmpty && DateTime.now().difference(cached.cachedAt).inHours < 4) {
      return List.from(cached.streams);
    }

    final s = song.streamUrl;

    // 1. Local offline files
    if (s.isNotEmpty && (s.startsWith('/') || s.startsWith('file://'))) {
      return [s];
    }

    // 2. Extract YouTube video ID
    String? videoId;
    if (song.id.startsWith('yt_')) {
      videoId = song.id.replaceFirst('yt_', '').trim();
    } else if (s.contains('youtube.com') || s.contains('youtu.be')) {
      videoId = YouTubeImporterService.extractVideoId(s);
    }

    // 3. If videoId found, extract direct YouTube audio streams
    if (videoId != null && videoId.isNotEmpty) {
      try {
        debugPrint('[NewPipe Engine] Resolving YouTube audio streams for $videoId ("${song.title}")...');
        final streams = await YouTubeImporterService.getAudioStreamUrls(videoId);
        if (streams.isNotEmpty) {
          debugPrint('[NewPipe Engine] Resolved ${streams.length} direct YouTube audio streams for "${song.title}"');
          _cacheStreams(cacheKey, streams);
          return streams;
        }
      } catch (e) {
        debugPrint('[NewPipe Engine] Direct extraction error for $videoId: $e');
      }
    }

    // 4. If no direct videoId, search YouTube dynamically by title + artist
    try {
      final cleanT = cleanTitle(song.title);
      final cleanA = song.artist != 'Unknown Artist' && song.artist.isNotEmpty ? song.artist.trim() : '';
      final query = cleanA.isNotEmpty ? '$cleanT $cleanA' : cleanT;
      debugPrint('[NewPipe Engine] Searching YouTube for "$query"...');

      final searchMatches = await YouTubeImporterService.searchYouTube(query, limit: 3);
      if (searchMatches.isNotEmpty) {
        final match = searchMatches.first;
        final matchVideoId = match.id.replaceFirst('yt_', '').trim();
        if (matchVideoId.isNotEmpty) {
          final streams = await YouTubeImporterService.getAudioStreamUrls(matchVideoId);
          if (streams.isNotEmpty) {
            debugPrint('[NewPipe Engine] Dynamic search resolved ${streams.length} streams for "$query"');
            _cacheStreams(cacheKey, streams);
            return streams;
          }
        }
      }
    } catch (e) {
      debugPrint('[NewPipe Engine] Dynamic search error for "${song.title}": $e');
    }

    return [];
  }
}
