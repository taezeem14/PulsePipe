import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_newpipe/models/song.dart';
import 'package:spotify_newpipe/models/playlist.dart';
import 'package:spotify_newpipe/services/sponsorblock_service.dart';
import 'package:spotify_newpipe/services/youtube_importer_service.dart';

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

    test('SponsorBlock service initializes safely and can be toggled', () {
      final service = SponsorBlockService.instance;
      expect(service.isEnabled, isFalse);
      service.isEnabled = true;
      expect(service.isEnabled, isTrue);
      service.isEnabled = false;
    });
  });
}
