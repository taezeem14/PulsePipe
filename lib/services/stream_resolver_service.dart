import 'package:flutter/foundation.dart';
import '../models/song.dart';
import 'youtube_importer_service.dart';

class StreamResolverService {
  static final Map<String, ({List<String> streams, DateTime cachedAt})> _resolvedCache = {};

  /// Invalidate cached stream candidates for a song if playback fails
  static void invalidateCache(String key) {
    _resolvedCache.remove(key);
  }

  /// Prefetch playable audio stream for a track in the background
  static void prefetchPlayableStreams(Song song) {
    resolvePlayableStreamCandidates(song).catchError((e) {
      debugPrint('[StreamResolverService] Prefetch background error for "${song.title}": $e');
      return <String>[];
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
          _resolvedCache[cacheKey] = (streams: streams, cachedAt: DateTime.now());
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
            _resolvedCache[cacheKey] = (streams: streams, cachedAt: DateTime.now());
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
