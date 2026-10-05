import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_newpipe/models/song.dart';
import 'package:spotify_newpipe/models/playlist.dart';
import 'package:spotify_newpipe/services/sponsorblock_service.dart';
import 'package:spotify_newpipe/services/youtube_importer_service.dart';
import 'package:http/http.dart' as http;

void main() {
  group('PulsePipe Music Architecture Tests', () {
    test('Song model initializes with correct metadata and serialization', () {
      const song = Song(
        id: 'yt_dQw4w9WgXcQ',
        title: 'Never Gonna Give You Up',
        artist: 'Rick Astley',
        duration: Duration(minutes: 3, seconds: 32),
        artworkUrl: 'https://img.youtube.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
        streamUrl: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      );

      expect(song.id, 'yt_dQw4w9WgXcQ');
      expect(song.title, 'Never Gonna Give You Up');
      expect(song.artist, 'Rick Astley');
      expect(song.duration.inSeconds, 212);
      expect(song.artworkUrl, isNotEmpty);
      expect(song.streamUrl, isNotEmpty);

      final map = song.toMap();
      final revived = Song.fromMap(map);
      expect(revived.id, song.id);
      expect(revived.title, song.title);
      expect(revived.artist, song.artist);
    });

    test('Playlist correctly adds and serializes songs', () {
      final playlist = Playlist(
        id: 'pl_favorites',
        title: 'Cyberpunk Mix',
        description: 'Synthwave & Electronic',
        coverUrl: '',
        songs: [],
        createdAt: DateTime.now(),
      );

      const track = Song(
        id: 'track_1',
        title: 'Resonance',
        artist: 'HOME',
        duration: Duration(minutes: 3, seconds: 32),
        artworkUrl: '',
        streamUrl: 'https://example.com/stream.mp3',
      );

      playlist.songs.add(track);
      expect(playlist.songs.length, 1);
      expect(playlist.songs.first.title, 'Resonance');

      final map = playlist.toMap();
      final revived = Playlist.fromMap(map);
      expect(revived.title, 'Cyberpunk Mix');
      expect(revived.songs.length, 1);
      expect(revived.songs.first.artist, 'HOME');
    });

    test('YouTube video ID parser extracts correctly from multiple URL formats', () {
      expect(
        YouTubeImporterService.extractVideoId('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
        'dQw4w9WgXcQ',
      );
      expect(
        YouTubeImporterService.extractVideoId('https://youtu.be/dQw4w9WgXcQ'),
        'dQw4w9WgXcQ',
      );
      expect(
        YouTubeImporterService.extractVideoId('https://music.youtube.com/watch?v=dQw4w9WgXcQ&feature=share'),
        'dQw4w9WgXcQ',
      );
      expect(
        YouTubeImporterService.extractVideoId('dQw4w9WgXcQ'),
        'dQw4w9WgXcQ',
      );
    });

    test('SponsorBlock service initializes with enabled state', () {
      final service = SponsorBlockService.instance;
      expect(service.isEnabled, isTrue);
    });

    test('Song.fromMap defensively parses heterogeneous data types without crashing', () {
      final dynamicMap = <String, dynamic>{
        'id': 12345, // int instead of String
        'title': 'Test Song',
        'artist': 'Test Artist',
        'duration_ms': '210000', // String instead of int
        'artwork_url': 'https://example.com/art.jpg',
        'stream_url': 'https://example.com/audio.mp3',
        'is_favorite': 1, // int 1 instead of boolean
      };

      final parsed = Song.fromMap(dynamicMap);
      expect(parsed.id, '12345');
      expect(parsed.duration.inMilliseconds, 210000);
      expect(parsed.isFavorite, isTrue);
    });

    test('Playlist.fromMap parses Map<dynamic, dynamic> without dropping tracks', () {
      final rawPlaylistMap = <dynamic, dynamic>{
        'id': 'pl_test',
        'title': 'Dynamic Test',
        'description': 'Description',
        'songs': [
          <dynamic, dynamic>{
            'id': 's1',
            'title': 'Track One',
            'artist': 'Artist One',
            'duration_ms': 180000,
            'artwork_url': '',
            'stream_url': 'https://example.com/1.mp3',
          }
        ],
        'createdAt': '2026-10-03T20:00:00.000Z',
      };

      final pl = Playlist.fromMap(Map<String, dynamic>.from(rawPlaylistMap));
      expect(pl.title, 'Dynamic Test');
      expect(pl.songs.length, 1);
      expect(pl.songs.first.title, 'Track One');
    });

    test('NewPipe stream resolver extracts high-speed audio candidates', () async {
      final urls = await YouTubeImporterService.getAudioStreamUrls('dQw4w9WgXcQ');
      expect(urls, isNotEmpty);
      expect(urls.length, lessThanOrEqualTo(3)); // Streamlined to top Opus/AAC candidates

      final client = http.Client();
      try {
        final resp = await client.get(
          Uri.parse(urls.first),
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0',
            'Range': 'bytes=0-65535',
            'Origin': 'https://www.youtube.com',
            'Referer': 'https://www.youtube.com/',
            'Sec-Fetch-Dest': 'empty',
            'Sec-Fetch-Mode': 'cors',
            'Sec-Fetch-Site': 'cross-site',
          },
        );
        expect(resp.statusCode, inInclusiveRange(200, 206));
        expect(resp.bodyBytes.length, greaterThan(0));
      } finally {
        client.close();
      }
    });
  });
}
