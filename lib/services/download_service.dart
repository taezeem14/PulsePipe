import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/song.dart';
import 'storage_service.dart';
import 'youtube_importer_service.dart';

class DownloadProgress {
  final String songId;
  final double progress; // 0.0 to 1.0
  final bool isCompleted;
  final bool isFailed;
  final String? error;
  final String? localFilePath;
  final bool isVideo;

  const DownloadProgress({
    required this.songId,
    required this.progress,
    this.isCompleted = false,
    this.isFailed = false,
    this.error,
    this.localFilePath,
    this.isVideo = false,
  });
}

class DownloadService {
  DownloadService._();

  static final Map<String, DownloadProgress> _activeDownloads = {};
  static final StreamController<DownloadProgress> _progressController =
      StreamController<DownloadProgress>.broadcast();

  static Stream<DownloadProgress> get progressStream => _progressController.stream;
  static Map<String, DownloadProgress> get activeDownloads => _activeDownloads;

  static String _sanitizeFilename(String input) {
    // Strip illegal filesystem and control characters
    var clean = input
        .replaceAll(RegExp(r'[\x00-\x1F\x7F\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // Strip trailing periods and spaces (prohibited on Windows)
    clean = clean.replaceAll(RegExp(r'[.\s]+$'), '');

    // Guard against Windows reserved device names
    const reserved = {
      'CON', 'PRN', 'AUX', 'NUL',
      'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
      'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9'
    };
    if (reserved.contains(clean.toUpperCase())) {
      clean = 'track_$clean';
    }

    return clean.isNotEmpty ? clean : 'track_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Locate or create appropriate public/accessible media directory cross-platform
  static Future<Directory> _getMediaDirectory({bool isVideo = false}) async {
    if (Platform.isAndroid) {
      try {
        final extList = await getExternalStorageDirectories(
          type: isVideo ? StorageDirectory.movies : StorageDirectory.downloads,
        );
        if (extList != null && extList.isNotEmpty) {
          final dir = Directory('${extList.first.path}/PulsePipe');
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }
          return dir;
        }
      } catch (_) {}

      try {
        final ext = await getExternalStorageDirectory();
        if (ext != null) {
          final dir = Directory('${ext.path}/PulsePipe');
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }
          return dir;
        }
      } catch (_) {}
    } else if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      try {
        final downloads = await getDownloadsDirectory();
        if (downloads != null) {
          final dir = Directory('${downloads.path}/PulsePipe');
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }
          return dir;
        }
      } catch (_) {}
    }

    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/PulsePipe');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Resolve any song to a valid YouTube Video ID
  static Future<String?> _resolveVideoId(YoutubeExplode yt, Song song) async {
    if (song.id.startsWith('yt_')) {
      return song.id.substring(3);
    }

    final fromUrl = YouTubeImporterService.extractVideoId(song.streamUrl);
    if (fromUrl != null && fromUrl.isNotEmpty) {
      return fromUrl;
    }

    try {
      final cleanTitle = song.title.replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), '').trim();
      final query = '${cleanTitle.isNotEmpty ? cleanTitle : song.title} ${song.artist}'.trim();
      final searchResults = await yt.search.search(query).timeout(const Duration(seconds: 8));
      if (searchResults.isNotEmpty) {
        return searchResults.first.id.value;
      }
    } catch (e) {
      debugPrint('[DownloadService] Error searching video ID for download: $e');
    }
    return null;
  }

  /// Download audio directly to device storage for offline playback
  static Future<String?> downloadAudio(Song song, StorageService storageService) async {
    final songId = song.id;

    // Check active in-progress downloads
    final active = _activeDownloads[songId];
    if (active != null && !active.isCompleted && !active.isFailed) {
      return null; // Already in progress
    }

    // Return immediately if already completed and file exists on disk
    if (active != null && active.isCompleted && active.localFilePath != null) {
      final f = File(active.localFilePath!);
      if (await f.exists() && await f.length() > 0) {
        return active.localFilePath;
      }
    }

    _activeDownloads[songId] = DownloadProgress(songId: songId, progress: 0.0);
    _progressController.add(_activeDownloads[songId]!);

    final yt = YoutubeExplode();
    try {
      final videoId = await _resolveVideoId(yt, song);
      if (videoId == null || videoId.isEmpty) {
        throw Exception('Could not resolve audio stream for "${song.title}"');
      }

      final manifest = await yt.videos.streamsClient.getManifest(videoId, requireWatchPage: false).timeout(const Duration(seconds: 12));

      // Prefer MP4/M4A AAC container for universal Android hardware playback, fallback to any audio
      StreamInfo? audioStreamInfo;
      final mp4Audio = manifest.audioOnly.where((s) => s.container.name.toLowerCase() == 'mp4').toList();
      if (mp4Audio.isNotEmpty) {
        audioStreamInfo = mp4Audio.withHighestBitrate();
      } else if (manifest.audioOnly.isNotEmpty) {
        audioStreamInfo = manifest.audioOnly.withHighestBitrate();
      } else if (manifest.audio.isNotEmpty) {
        audioStreamInfo = manifest.audio.withHighestBitrate();
      } else {
        throw Exception('No audio stream found for "${song.title}"');
      }

      final dir = await _getMediaDirectory(isVideo: false);
      final rawBase = _sanitizeFilename('${song.title} - ${song.artist}');
      final safeBase = rawBase.length > 90 ? rawBase.substring(0, 90).trimRight() : rawBase;
      final safeId = song.id.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
      final ext = audioStreamInfo.container.name.toLowerCase() == 'mp4' ? 'm4a' : audioStreamInfo.container.name.toLowerCase();
      final file = File('${dir.path}/${safeBase}_$safeId.$ext');
      final partFile = File('${file.path}.part');

      final stream = yt.videos.streamsClient.get(audioStreamInfo);
      IOSink? output;
      try {
        output = partFile.openWrite();
        var received = 0;
        final total = audioStreamInfo.size.totalBytes;

        await for (final chunk in stream.timeout(const Duration(seconds: 30))) {
          output.add(chunk);
          received += chunk.length;
          final prog = total > 0 ? (received / total).clamp(0.0, 1.0) : 0.5;
          _activeDownloads[songId] = DownloadProgress(songId: songId, progress: prog);
          _progressController.add(_activeDownloads[songId]!);
        }

        await output.flush();
        await output.close();
        output = null;

        if (await file.exists()) {
          try { await file.delete(); } catch (_) {}
        }
        await partFile.rename(file.path);
      } catch (e) {
        try { await output?.close(); } catch (_) {}
        output = null;
        if (await partFile.exists()) {
          try { await partFile.delete(); } catch (_) {}
        }
        rethrow;
      }

      // Record in storage as downloaded
      final downloadedSong = song.copyWith(
        streamUrl: file.path, // Use local path for offline playback
        source: 'download',
      );
      final currentDownloads = storageService.loadDownloads();
      currentDownloads.removeWhere((s) => s.id == song.id);
      currentDownloads.add(downloadedSong);
      await storageService.saveDownloads(currentDownloads);

      _activeDownloads[songId] = DownloadProgress(
        songId: songId,
        progress: 1.0,
        isCompleted: true,
        localFilePath: file.path,
      );
      _progressController.add(_activeDownloads[songId]!);
      return file.path;
    } catch (e) {
      debugPrint('[DownloadService] Audio download error: $e');
      _activeDownloads[songId] = DownloadProgress(
        songId: songId,
        progress: 0.0,
        isFailed: true,
        error: e.toString(),
      );
      _progressController.add(_activeDownloads[songId]!);
      return null;
    } finally {
      yt.close();
    }
  }

  /// Download MP4 Video directly to device Movies folder
  static Future<String?> downloadVideo(Song song) async {
    final videoIdKey = 'video_${song.id}';
    final active = _activeDownloads[videoIdKey];
    if (active != null && !active.isCompleted && !active.isFailed) {
      return null; // Already downloading
    }

    _activeDownloads[videoIdKey] = DownloadProgress(songId: videoIdKey, progress: 0.0, isVideo: true);
    _progressController.add(_activeDownloads[videoIdKey]!);

    final yt = YoutubeExplode();
    try {
      final videoId = await _resolveVideoId(yt, song);
      if (videoId == null || videoId.isEmpty) {
        throw Exception('No video found for "${song.title}"');
      }

      final manifest = await yt.videos.streamsClient.getManifest(videoId, requireWatchPage: false).timeout(const Duration(seconds: 12));

      // Strictly prioritize muxed streams (both video AND audio track in MP4 container)
      StreamInfo? streamInfo;
      final muxedStreams = manifest.muxed.sortByVideoQuality();
      if (muxedStreams.isNotEmpty) {
        streamInfo = muxedStreams.first;
      } else {
        throw Exception('No playable audio/video muxed stream available for "${song.title}"');
      }

      final dir = await _getMediaDirectory(isVideo: true);
      final rawBase = _sanitizeFilename('${song.title} - ${song.artist}');
      final safeBase = rawBase.length > 90 ? rawBase.substring(0, 90).trimRight() : rawBase;
      final safeId = song.id.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
      final file = File('${dir.path}/${safeBase}_$safeId.mp4');
      final partFile = File('${file.path}.part');

      final stream = yt.videos.streamsClient.get(streamInfo);
      IOSink? output;
      try {
        output = partFile.openWrite();
        var received = 0;
        final total = streamInfo.size.totalBytes;

        await for (final chunk in stream.timeout(const Duration(seconds: 30))) {
          output.add(chunk);
          received += chunk.length;
          final prog = total > 0 ? (received / total).clamp(0.0, 1.0) : 0.5;
          _activeDownloads[videoIdKey] = DownloadProgress(
            songId: videoIdKey,
            progress: prog,
            isVideo: true,
          );
          _progressController.add(_activeDownloads[videoIdKey]!);
        }

        await output.flush();
        await output.close();
        output = null;

        if (await file.exists()) {
          try { await file.delete(); } catch (_) {}
        }
        await partFile.rename(file.path);
      } catch (e) {
        try { await output?.close(); } catch (_) {}
        output = null;
        if (await partFile.exists()) {
          try { await partFile.delete(); } catch (_) {}
        }
        rethrow;
      }

      _activeDownloads[videoIdKey] = DownloadProgress(
        songId: videoIdKey,
        progress: 1.0,
        isCompleted: true,
        localFilePath: file.path,
        isVideo: true,
      );
      _progressController.add(_activeDownloads[videoIdKey]!);
      return file.path;
    } catch (e) {
      debugPrint('[DownloadService] Video download error: $e');
      _activeDownloads[videoIdKey] = DownloadProgress(
        songId: videoIdKey,
        progress: 0.0,
        isFailed: true,
        error: e.toString(),
        isVideo: true,
      );
      _progressController.add(_activeDownloads[videoIdKey]!);
      return null;
    } finally {
      yt.close();
    }
  }
}
