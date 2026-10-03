import 'dart:convert';
import 'package:http/http.dart' as http;

class SponsorSegment {
  final double start;
  final double end;
  final String category;

  SponsorSegment({
    required this.start,
    required this.end,
    required this.category,
  });
}

class SponsorBlockService {
  static final SponsorBlockService instance = SponsorBlockService._();
  SponsorBlockService._();

  // Disabled by default for music playback to prevent community intro/outro markers from clipping tracks
  bool isEnabled = false;

  // Cache segment results by stream ID
  final Map<String, List<SponsorSegment>> _segmentCache = {};

  Future<List<SponsorSegment>> getSkipSegments(String videoId) async {
    if (!isEnabled || videoId.isEmpty) return [];

    if (_segmentCache.containsKey(videoId)) {
      return _segmentCache[videoId]!;
    }

    try {
      // Query strictly paid sponsorship ads — NEVER intro or outro for music tracks
      final uri = Uri.parse(
        'https://sponsor.ajay.app/api/skipSegments?videoID=$videoId&categories=["sponsor"]',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
        final segments = data.map((item) {
          final segment = (item['segment'] as List<dynamic>?) ?? [0, 0];
          return SponsorSegment(
            start: (segment[0] as num).toDouble(),
            end: (segment[1] as num).toDouble(),
            category: item['category'] as String? ?? 'sponsor',
          );
        }).toList();

        _segmentCache[videoId] = segments;
        return segments;
      }
    } catch (_) {
      // Offline fallback: graceful return empty segments
    }

    return [];
  }
}
