import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';
import '../models/playlist.dart';

class StorageService {
  static const String _favsKey = 'sine_favorites_v1';
  static const String _favsLegacyKey = 'ember_favorites_v1';
  static const String _histKey = 'sine_history_v1';
  static const String _histLegacyKey = 'ember_history_v1';
  static const String _speedKey = 'sine_playback_speed';
  static const String _speedLegacyKey = 'ember_playback_speed';
  static const String _playlistsKey = 'sine_playlists_v1';
  static const String _playlistsLegacyKey = 'ember_playlists_v1';
  static const String _downloadsKey = 'sine_downloads_v1';
  static const String _downloadsLegacyKey = 'ember_downloads_v1';
  static const String _eqPresetKey = 'sine_eq_preset';
  static const String _eqPresetLegacyKey = 'ember_eq_preset';
  static const String _eqEnabledKey = 'sine_eq_enabled';
  static const String _eqEnabledLegacyKey = 'ember_eq_enabled';
  static const String _eqBassBoostKey = 'sine_eq_bass_boost';
  static const String _eqBassBoostLegacyKey = 'ember_eq_bass_boost';
  static const String _eqBandGainsKey = 'sine_eq_band_gains';
  static const String _eqBandGainsLegacyKey = 'ember_eq_band_gains';
  static const String _repeatModeKey = 'sine_repeat_mode';
  static const String _repeatModeLegacyKey = 'pulsepipe_repeat_mode';
  static const String _shuffleKey = 'sine_shuffle';
  static const String _shuffleLegacyKey = 'pulsepipe_shuffle';

  final SharedPreferences? _prefs;
  final List<Song> _memFavorites = [];
  final List<Song> _memHistory = [];
  final List<Playlist> _memPlaylists = [];
  final List<Song> _memDownloads = [];
  double _memSpeed = 1.0;

  StorageService(this._prefs);

  static Future<StorageService> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final service = StorageService(prefs);
      await service.purgeAllPlaceholders();
      return service;
    } catch (e) {
      return StorageService(null);
    }
  }

  /// Purges all legacy mock / placeholder songs from all storage keys permanently
  Future<void> purgeAllPlaceholders() async {
    final favs = loadFavorites();
    await saveFavorites(favs);

    final hist = loadHistory();
    await saveHistory(hist);

    final pl = loadPlaylists();
    await savePlaylists(pl);

    final dl = loadDownloads();
    await saveDownloads(dl);
  }

  List<Song> loadFavorites() {
    if (_prefs == null) {
      return List.unmodifiable(_memFavorites.where((s) => !Song.isPlaceholder(s)));
    }
    final raw = _prefs.getStringList(_favsKey) ?? _prefs.getStringList(_favsLegacyKey) ?? [];
    final cleaned = raw
        .map((s) {
          try {
            final decoded = jsonDecode(s);
            if (decoded is! Map) return null;
            final song = Song.fromMap(Map<String, dynamic>.from(decoded));
            return Song.isPlaceholder(song) ? null : song;
          } catch (_) {
            return null;
          }
        })
        .whereType<Song>()
        .toList();

    _memFavorites.clear();
    _memFavorites.addAll(cleaned);

    if (raw.length != cleaned.length) {
      final encoded = cleaned.map((s) => jsonEncode(s.toMap())).toList();
      _prefs.setStringList(_favsKey, encoded);
    }

    return cleaned;
  }

  Future<void> saveFavorites(List<Song> songs) async {
    final cleaned = songs.where((s) => !Song.isPlaceholder(s)).toList();
    _memFavorites.clear();
    _memFavorites.addAll(cleaned);
    if (_prefs != null) {
      final encoded = cleaned.map((s) => jsonEncode(s.toMap())).toList();
      await _prefs.setStringList(_favsKey, encoded);
    }
  }

  List<Song> loadHistory() {
    if (_prefs == null) {
      return List.unmodifiable(_memHistory.where((s) => !Song.isPlaceholder(s)));
    }
    final raw = _prefs.getStringList(_histKey) ?? _prefs.getStringList(_histLegacyKey) ?? [];
    final cleaned = raw
        .map((s) {
          try {
            final decoded = jsonDecode(s);
            if (decoded is! Map) return null;
            final song = Song.fromMap(Map<String, dynamic>.from(decoded));
            return Song.isPlaceholder(song) ? null : song;
          } catch (_) {
            return null;
          }
        })
        .whereType<Song>()
        .toList();

    _memHistory.clear();
    _memHistory.addAll(cleaned);

    if (raw.length != cleaned.length) {
      final encoded = cleaned.map((s) => jsonEncode(s.toMap())).toList();
      _prefs.setStringList(_histKey, encoded);
    }

    return cleaned;
  }

  Future<void> saveHistory(List<Song> songs) async {
    final cleaned = songs.where((s) => !Song.isPlaceholder(s)).take(200).toList();
    _memHistory.clear();
    _memHistory.addAll(cleaned);
    if (_prefs != null) {
      final encoded = cleaned.map((s) => jsonEncode(s.toMap())).toList();
      await _prefs.setStringList(_histKey, encoded);
    }
  }

  Future<void> clearHistory() async {
    _memHistory.clear();
    if (_prefs != null) {
      await _prefs.remove(_histKey);
    }
  }

  List<Playlist> loadPlaylists() {
    if (_prefs == null) {
      return List<Playlist>.from(_memPlaylists);
    }
    final raw = _prefs.getStringList(_playlistsKey) ?? _prefs.getStringList(_playlistsLegacyKey) ?? [];
    final list = <Playlist>[];
    for (final s in raw) {
      try {
        final decoded = jsonDecode(s);
        if (decoded is! Map) continue;
        final pl = Playlist.fromMap(Map<String, dynamic>.from(decoded));
        final sanitizedSongs = pl.songs.where((song) => !Song.isPlaceholder(song)).toList();
        list.add(pl.copyWith(songs: sanitizedSongs));
      } catch (_) {}
    }

    _memPlaylists.clear();
    _memPlaylists.addAll(list);

    if (raw.length != list.length) {
      final encoded = list.map((p) => jsonEncode(p.toMap())).toList();
      _prefs.setStringList(_playlistsKey, encoded);
    }

    return list;
  }

  Future<void> savePlaylists(List<Playlist> playlists) async {
    _memPlaylists.clear();
    _memPlaylists.addAll(playlists);
    if (_prefs != null) {
      final encoded = playlists.map((p) => jsonEncode(p.toMap())).toList();
      await _prefs.setStringList(_playlistsKey, encoded);
    }
  }

  Future<void> savePlaylist(Playlist playlist) async {
    final list = List<Playlist>.from(loadPlaylists());
    final idx = list.indexWhere((p) => p.id == playlist.id);
    if (idx != -1) {
      list[idx] = playlist;
    } else {
      list.insert(0, playlist);
    }
    await savePlaylists(list);
  }

  Future<void> deletePlaylist(String playlistId) async {
    final list = List<Playlist>.from(loadPlaylists());
    list.removeWhere((p) => p.id == playlistId);
    await savePlaylists(list);
  }

  Future<void> addSongToPlaylist(String playlistId, Song song) async {
    if (Song.isPlaceholder(song)) return;
    final list = List<Playlist>.from(loadPlaylists());
    final idx = list.indexWhere((p) => p.id == playlistId);
    if (idx != -1) {
      final existing = list[idx];
      if (!existing.songs.any((s) => s.id == song.id)) {
        final updatedSongs = List<Song>.from(existing.songs)..add(song);
        final updated = existing.copyWith(
          songs: updatedSongs,
          coverUrl: existing.coverUrl ?? (song.artworkUrl.isNotEmpty ? song.artworkUrl : null),
        );
        list[idx] = updated;
        await savePlaylists(list);
      }
    }
  }

  List<Song> loadDownloads() {
    if (_prefs == null) {
      return List<Song>.from(_memDownloads.where((s) => !Song.isPlaceholder(s)));
    }
    final raw = _prefs.getStringList(_downloadsKey) ?? _prefs.getStringList(_downloadsLegacyKey) ?? [];
    final cleaned = raw
        .map((s) {
          try {
            final decoded = jsonDecode(s);
            if (decoded is! Map) return null;
            final song = Song.fromMap(Map<String, dynamic>.from(decoded));
            return Song.isPlaceholder(song) ? null : song;
          } catch (_) {
            return null;
          }
        })
        .whereType<Song>()
        .toList();

    _memDownloads.clear();
    _memDownloads.addAll(cleaned);

    if (raw.length != cleaned.length) {
      final encoded = cleaned.map((s) => jsonEncode(s.toMap())).toList();
      _prefs.setStringList(_downloadsKey, encoded);
    }

    return cleaned;
  }

  Future<void> saveDownloads(List<Song> songs) async {
    final cleaned = songs.where((s) => !Song.isPlaceholder(s)).toList();
    _memDownloads.clear();
    _memDownloads.addAll(cleaned);
    if (_prefs != null) {
      final encoded = cleaned.map((s) => jsonEncode(s.toMap())).toList();
      await _prefs.setStringList(_downloadsKey, encoded);
    }
  }

  String loadRepeatMode() {
    return _prefs?.getString(_repeatModeKey) ?? _prefs?.getString(_repeatModeLegacyKey) ?? 'off';
  }

  Future<void> saveRepeatMode(String mode) async {
    await _prefs?.setString(_repeatModeKey, mode);
  }

  bool loadShuffle() {
    return _prefs?.getBool(_shuffleKey) ?? _prefs?.getBool(_shuffleLegacyKey) ?? false;
  }

  Future<void> saveShuffle(bool shuffle) async {
    await _prefs?.setBool(_shuffleKey, shuffle);
  }

  double loadPlaybackSpeed() {
    return _prefs?.getDouble(_speedKey) ?? _prefs?.getDouble(_speedLegacyKey) ?? _memSpeed;
  }

  Future<void> savePlaybackSpeed(double speed) async {
    _memSpeed = speed;
    await _prefs?.setDouble(_speedKey, speed);
  }

  String loadEqualizerPreset() {
    return _prefs?.getString(_eqPresetKey) ?? _prefs?.getString(_eqPresetLegacyKey) ?? 'Flat';
  }

  Future<void> saveEqualizerPreset(String preset) async {
    await _prefs?.setString(_eqPresetKey, preset);
  }

  bool loadEqualizerEnabled() {
    return _prefs?.getBool(_eqEnabledKey) ?? _prefs?.getBool(_eqEnabledLegacyKey) ?? false;
  }

  Future<void> saveEqualizerEnabled(bool enabled) async {
    await _prefs?.setBool(_eqEnabledKey, enabled);
  }

  double loadBassBoost() {
    return _prefs?.getDouble(_eqBassBoostKey) ?? _prefs?.getDouble(_eqBassBoostLegacyKey) ?? 0.0;
  }

  Future<void> saveBassBoost(double gain) async {
    await _prefs?.setDouble(_eqBassBoostKey, gain);
  }

  Map<int, double> loadBandGains() {
    final raw = _prefs?.getString(_eqBandGainsKey) ?? _prefs?.getString(_eqBandGainsLegacyKey);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(int.parse(k.toString()), (v as num).toDouble()));
      }
      return {};
    } catch (_) {
      return {};
    }
  }

  Future<void> saveBandGains(Map<int, double> gains) async {
    final stringMap = gains.map((k, v) => MapEntry(k.toString(), v));
    await _prefs?.setString(_eqBandGainsKey, jsonEncode(stringMap));
  }
}
