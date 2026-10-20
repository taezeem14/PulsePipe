import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/song.dart';
import 'storage_service.dart';
import 'youtube_importer_service.dart';
import 'piped_service.dart';

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
      // 1. Primary target requested: /storage/emulated/0/Sine-Music (same parent as Android and DCIM)
      try {
        final rootDir = Directory('/storage/emulated/0/Sine-Music');
        if (!await rootDir.exists()) {
          await rootDir.create(recursive: true);
        }
        return rootDir;
      } catch (e) {
        debugPrint('[DownloadService] Direct /storage/emulated/0/Sine-Music access notice: $e');
      }

      // 2. Derive root directory by stripping /Android from getExternalStorageDirectory()
      try {
        final ext = await getExternalStorageDirectory();
        if (ext != null) {
          final path = ext.path;
          final androidIdx = path.indexOf('/Android');
          final rootPath = androidIdx != -1 ? path.substring(0, androidIdx) : path;
          final dir = Directory('$rootPath/Sine-Music');
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }
          return dir;
        }
      } catch (_) {}

      // 3. Fallback to standard Music directory on primary external storage
      try {
        final musicDir = Directory('/storage/emulated/0/Music/Sine-Music');
        if (!await musicDir.exists()) {
          await musicDir.create(recursive: true);
        }
        return musicDir;
      } catch (_) {}

      // 4. Fallback to standard Download directory on primary external storage
      try {
        final dlDir = Directory('/storage/emulated/0/Download/Sine-Music');
        if (!await dlDir.exists()) {
          await dlDir.create(recursive: true);
        }
        return dlDir;
      } catch (_) {}
    } else if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      try {
        final downloads = await getDownloadsDirectory();
        if (downloads != null) {
          final dir = Directory('${downloads.path}/Sine-Music');
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }
          return dir;
        }
      } catch (_) {}
    }

    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/Sine-Music');
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
  /// Helper to stream download from an HTTP / Piped proxy URL directly to a file
  static Future<bool> _downloadFileFromUrl({
    required String url,
    required File targetFile,
    required String downloadKey,
    required bool isVideo,
  }) async {
    final partFile = File('${targetFile.path}.part');
    IOSink? output;
    http.Client? client;
    try {
      client = http.Client();
      final req = http.Request('GET', Uri.parse(url));
      req.headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36';
      req.headers['Accept'] = '*/*';

      final response = await client.send(req).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200 && response.statusCode != 206) {
        throw Exception('Server returned HTTP ${response.statusCode}');
      }

      output = partFile.openWrite();
      var received = 0;
      final total = response.contentLength ?? 0;
      double lastProgress = 0.0;

      await for (final chunk in response.stream.timeout(const Duration(seconds: 35))) {
        output.add(chunk);
        received += chunk.length;
        final prog = total > 0 ? (received / total).clamp(0.0, 1.0) : 0.5;
        if ((prog - lastProgress).abs() >= 0.01 || prog == 1.0) {
          lastProgress = prog;
          _activeDownloads[downloadKey] = DownloadProgress(
            songId: downloadKey,
            progress: prog,
            isVideo: isVideo,
          );
          _progressController.add(_activeDownloads[downloadKey]!);
        }
      }

      await output.flush();
      await output.close();
      output = null;

      if (await targetFile.exists()) {
        try { await targetFile.delete(); } catch (_) {}
      }
      await partFile.rename(targetFile.path);
      return true;
    } catch (e) {
      try { await output?.close(); } catch (_) {}
      output = null;
      if (await partFile.exists()) {
        try { await partFile.delete(); } catch (_) {}
      }
      rethrow;
    } finally {
      client?.close();
    }
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

    final dir = await _getMediaDirectory(isVideo: false);
    final rawBase = _sanitizeFilename('${song.title} - ${song.artist}');
    final safeBase = rawBase.length > 90 ? rawBase.substring(0, 90).trimRight() : rawBase;
    final safeId = song.id.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final targetM4a = File('${dir.path}/${safeBase}_$safeId.m4a');

    if (await targetM4a.exists() && await targetM4a.length() > 0) {
      _activeDownloads[songId] = DownloadProgress(
        songId: songId,
        progress: 1.0,
        isCompleted: true,
        localFilePath: targetM4a.path,
      );
      _progressController.add(_activeDownloads[songId]!);
      return targetM4a.path;
    }

    _activeDownloads[songId] = DownloadProgress(songId: songId, progress: 0.0);
    _progressController.add(_activeDownloads[songId]!);

    final yt = YoutubeExplode();
    try {
      final videoId = await _resolveVideoId(yt, song);
      if (videoId == null || videoId.isEmpty) {
        throw Exception('Could not resolve audio stream for "${song.title}"');
      }

      StreamManifest? manifest;
      try {
        manifest = await yt.videos.streamsClient.getManifest(
          videoId,
          ytClients: [
            YoutubeApiClient.ios,
            YoutubeApiClient.android,
            YoutubeApiClient.androidSdkless,
          ],
          requireWatchPage: false,
        ).timeout(const Duration(seconds: 10));
      } catch (e) {
        debugPrint('[DownloadService] InnerTube manifest query failed ($e), retrying watch page...');
        try {
          manifest = await yt.videos.streamsClient.getManifest(
            videoId,
            ytClients: [
              YoutubeApiClient.ios,
              YoutubeApiClient.tv,
            ],
            requireWatchPage: true,
          ).timeout(const Duration(seconds: 12));
        } catch (_) {}
      }

      File? completedFile;

      if (manifest != null) {
        StreamInfo? audioStreamInfo;
        final mp4Audio = manifest.audioOnly.where((s) => s.container.name.toLowerCase() == 'mp4').toList();
        if (mp4Audio.isNotEmpty) {
          audioStreamInfo = mp4Audio.withHighestBitrate();
        } else if (manifest.audioOnly.isNotEmpty) {
          audioStreamInfo = manifest.audioOnly.withHighestBitrate();
        } else if (manifest.audio.isNotEmpty) {
          audioStreamInfo = manifest.audio.withHighestBitrate();
        }

        if (audioStreamInfo != null) {
          final ext = audioStreamInfo.container.name.toLowerCase() == 'mp4' ? 'm4a' : audioStreamInfo.container.name.toLowerCase();
          final file = File('${dir.path}/${safeBase}_$safeId.$ext');
          final partFile = File('${file.path}.part');

          try {
            final stream = yt.videos.streamsClient.get(audioStreamInfo);
            IOSink? output;
            try {
              output = partFile.openWrite();
              var received = 0;
              final total = audioStreamInfo.size.totalBytes;
              double lastProgress = 0.0;

              await for (final chunk in stream.timeout(const Duration(seconds: 35))) {
                output.add(chunk);
                received += chunk.length;
                final prog = total > 0 ? (received / total).clamp(0.0, 1.0) : 0.5;
                if ((prog - lastProgress).abs() >= 0.01 || prog == 1.0) {
                  lastProgress = prog;
                  _activeDownloads[songId] = DownloadProgress(songId: songId, progress: prog);
                  _progressController.add(_activeDownloads[songId]!);
                }
              }

              await output.flush();
              await output.close();
              output = null;

              if (await file.exists()) {
                try { await file.delete(); } catch (_) {}
              }
              await partFile.rename(file.path);
              completedFile = file;
            } catch (e) {
              try { await output?.close(); } catch (_) {}
              output = null;
              if (await partFile.exists()) {
                try { await partFile.delete(); } catch (_) {}
              }
              debugPrint('[DownloadService] Direct audio download stream failed: $e, falling back to Piped proxy...');
            }
          } catch (_) {}
        }
      }

      // Fallback: If YouTubeExplode audio failed or threw 403, download through Piped proxy
      if (completedFile == null) {
        debugPrint('[DownloadService] Attempting Piped audio proxy fallback for download of "${song.title}"...');
        final pipedAudioUrl = await PipedService.getAudioStream(videoId);
        if (pipedAudioUrl == null || pipedAudioUrl.isEmpty) {
          throw Exception('Unable to acquire audio stream from YouTube or Piped proxy for "${song.title}"');
        }

        final file = File('${dir.path}/${safeBase}_$safeId.m4a');
        await _downloadFileFromUrl(
          url: pipedAudioUrl,
          targetFile: file,
          downloadKey: songId,
          isVideo: false,
        );
        completedFile = file;
      }

      // Record in storage as downloaded
      final downloadedSong = song.copyWith(
        streamUrl: completedFile.path, // Use local path for offline playback
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
        localFilePath: completedFile.path,
      );
      _progressController.add(_activeDownloads[songId]!);
      return completedFile.path;
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

  /// Download MP4 Video (complete with audio) directly to device Movies folder
  static Future<String?> downloadVideo(Song song) async {
    final videoIdKey = 'video_${song.id}';
    final active = _activeDownloads[videoIdKey];
    if (active != null && !active.isCompleted && !active.isFailed) {
      return null; // Already downloading
    }

    final dir = await _getMediaDirectory(isVideo: true);
    final rawBase = _sanitizeFilename('${song.title} - ${song.artist}');
    final safeBase = rawBase.length > 90 ? rawBase.substring(0, 90).trimRight() : rawBase;
    final safeId = song.id.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final targetMp4 = File('${dir.path}/${safeBase}_$safeId.mp4');

    // Return immediately if already downloaded and exists on disk
    if (await targetMp4.exists() && await targetMp4.length() > 0) {
      _activeDownloads[videoIdKey] = DownloadProgress(
        songId: videoIdKey,
        progress: 1.0,
        isCompleted: true,
        localFilePath: targetMp4.path,
        isVideo: true,
      );
      _progressController.add(_activeDownloads[videoIdKey]!);
      return targetMp4.path;
    }

    _activeDownloads[videoIdKey] = DownloadProgress(songId: videoIdKey, progress: 0.0, isVideo: true);
    _progressController.add(_activeDownloads[videoIdKey]!);

    final yt = YoutubeExplode();
    try {
      final videoId = await _resolveVideoId(yt, song);
      if (videoId == null || videoId.isEmpty) {
        throw Exception('No video found for "${song.title}"');
      }

      StreamManifest? manifest;

      // Tier 1: Query iOS & Android clients without watch page
      // iOS Innertube client returns progressive muxed formats (itag 22 @ 720p, itag 18 @ 360p)
      try {
        manifest = await yt.videos.streamsClient.getManifest(
          videoId,
          ytClients: [
            YoutubeApiClient.ios,
            YoutubeApiClient.android,
            YoutubeApiClient.androidSdkless,
          ],
          requireWatchPage: false,
        ).timeout(const Duration(seconds: 10));
      } catch (tier1Err) {
        debugPrint('[DownloadService] Tier 1 manifest fetch failed ($tier1Err), attempting Tier 2...');
      }

      // Tier 2: Watch page fallback if Tier 1 failed or returned no muxed streams
      if (manifest == null || manifest.muxed.isEmpty) {
        try {
          manifest = await yt.videos.streamsClient.getManifest(
            videoId,
            ytClients: [
              YoutubeApiClient.ios,
              YoutubeApiClient.tv,
              YoutubeApiClient.androidVr,
            ],
            requireWatchPage: true,
          ).timeout(const Duration(seconds: 12));
        } catch (tier2Err) {
          debugPrint('[DownloadService] Tier 2 watch page manifest fetch failed: $tier2Err');
        }
      }

      File? completedFile;

      if (manifest != null && manifest.muxed.isNotEmpty) {
        MuxedStreamInfo? selectedStream;

        // 1. Prefer itag 22 (720p HD MP4 muxed: H.264 + AAC audio)
        for (final s in manifest.muxed) {
          if (s.tag == 22) {
            selectedStream = s;
            break;
          }
        }

        // 2. Fallback: Any MP4 muxed stream sorted by highest video resolution
        if (selectedStream == null) {
          final mp4Muxed = manifest.muxed
              .where((s) => s.container.name.toLowerCase() == 'mp4')
              .sortByVideoQuality();
          if (mp4Muxed.isNotEmpty) {
            selectedStream = mp4Muxed.first;
          }
        }

        // 3. Fallback: itag 18 (360p SD MP4 muxed: H.264 + AAC audio)
        if (selectedStream == null) {
          for (final s in manifest.muxed) {
            if (s.tag == 18) {
              selectedStream = s;
              break;
            }
          }
        }

        // 4. Fallback: Any available muxed stream
        if (selectedStream == null && manifest.muxed.isNotEmpty) {
          selectedStream = manifest.muxed.sortByVideoQuality().first;
        }

        if (selectedStream != null) {
          final ext = selectedStream.container.name.toLowerCase() == 'webm' ? 'webm' : 'mp4';
          final file = File('${dir.path}/${safeBase}_$safeId.$ext');
          final partFile = File('${file.path}.part');

          try {
            final stream = yt.videos.streamsClient.get(selectedStream);
            IOSink? output;
            try {
              output = partFile.openWrite();
              var received = 0;
              final total = selectedStream.size.totalBytes;
              double lastReportedProgress = 0.0;

              await for (final chunk in stream.timeout(const Duration(seconds: 35))) {
                output.add(chunk);
                received += chunk.length;
                final prog = total > 0 ? (received / total).clamp(0.0, 1.0) : 0.5;

                // Throttle progress updates to 1% intervals for smooth UI
                if ((prog - lastReportedProgress).abs() >= 0.01 || prog == 1.0) {
                  lastReportedProgress = prog;
                  _activeDownloads[videoIdKey] = DownloadProgress(
                    songId: videoIdKey,
                    progress: prog,
                    isVideo: true,
                  );
                  _progressController.add(_activeDownloads[videoIdKey]!);
                }
              }

              await output.flush();
              await output.close();
              output = null;

              if (await file.exists()) {
                try { await file.delete(); } catch (_) {}
              }
              await partFile.rename(file.path);
              completedFile = file;
            } catch (e) {
              try { await output?.close(); } catch (_) {}
              output = null;
              if (await partFile.exists()) {
                try { await partFile.delete(); } catch (_) {}
              }
              debugPrint('[DownloadService] YouTube direct video download stream failed: $e');
            }
          } catch (_) {}
        }
      }

      // Tier 3 Fallback: If YouTubeExplode returned no muxed streams or download severed, use Piped muxed video stream
      if (completedFile == null) {
        debugPrint('[DownloadService] Attempting Piped proxy video fallback for "${song.title}"...');
        final pipedVideoUrl = await PipedService.getVideoStream(videoId);
        if (pipedVideoUrl == null || pipedVideoUrl.isEmpty) {
          throw Exception('No playable audio/video muxed stream available for "${song.title}" via YouTube or Piped proxy.');
        }

        final file = File('${dir.path}/${safeBase}_$safeId.mp4');
        await _downloadFileFromUrl(
          url: pipedVideoUrl,
          targetFile: file,
          downloadKey: videoIdKey,
          isVideo: true,
        );
        completedFile = file;
      }

      _activeDownloads[videoIdKey] = DownloadProgress(
        songId: videoIdKey,
        progress: 1.0,
        isCompleted: true,
        localFilePath: completedFile.path,
        isVideo: true,
      );
      _progressController.add(_activeDownloads[videoIdKey]!);
      return completedFile.path;
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
