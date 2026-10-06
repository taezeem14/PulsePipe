import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import '../models/song.dart';
import 'stream_resolver_service.dart';
import 'sponsorblock_service.dart';
import 'youtube_importer_service.dart';
import 'piped_service.dart';
import 'log_service.dart';


Future<AudioHandler> initAudioHandler() async {
  try {
    return await AudioService.init(
      builder: () => EmberAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.taezeem.ember.channel.audio',
        androidNotificationChannelName: 'Ember Music Playback',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
        androidNotificationIcon: 'mipmap/ic_launcher',
      ),
    ).timeout(
      const Duration(seconds: 4),
      onTimeout: () {
        debugPrint('AudioService.init timeout -> using fallback local EmberAudioHandler');
        return EmberAudioHandler();
      },
    );
  } catch (e, st) {
    debugPrint('AudioService.init error: $e\n$st -> using fallback local EmberAudioHandler');
    return EmberAudioHandler();
  }
}

class EmberAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AndroidEqualizer _equalizer = AndroidEqualizer();
  final AndroidLoudnessEnhancer _loudnessEnhancer = AndroidLoudnessEnhancer();
  late final AudioPlayer _player;

  Song? _currentSong;
  AsyncCallback? _onSkipNext;
  AsyncCallback? _onSkipPrevious;
  AsyncCallback? _onCompleted;
  ValueChanged<Song>? _onPlaybackFailed;

  /// Guard to prevent ProcessingState.completed from firing _onCompleted
  /// multiple times or prematurely during loading/transitioning
  bool _completionHandled = true;
  bool _currentTrackActive = false;
  bool _wasPlayingBeforeInterrupt = false;
  double _preDuckVolume = 1.0;

  bool _eqEnabled = false;
  double _bassBoost = 0.0;
  String _currentPreset = 'Flat';

  List<SponsorSegment> _activeSponsorSegments = [];
  final Set<String> _skippedSegmentKeys = {};
  bool _isSkippingSponsor = false;

  /// NewPipe YouTube streaming headers for ExoPlayer HTTP data source
  static const Map<String, String> _youtubeHeaders = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0',
    'Origin': 'https://www.youtube.com',
    'Referer': 'https://www.youtube.com/',
    'Sec-Fetch-Dest': 'empty',
    'Sec-Fetch-Mode': 'cors',
    'Sec-Fetch-Site': 'cross-site',
    'Accept': '*/*',
  };


  EmberAudioHandler() {
    _player = AudioPlayer(
      audioLoadConfiguration: const AudioLoadConfiguration(
        androidLoadControl: AndroidLoadControl(
          minBufferDuration: Duration(seconds: 15),
          maxBufferDuration: Duration(seconds: 45),
          bufferForPlaybackDuration: Duration(milliseconds: 500),
          bufferForPlaybackAfterRebufferDuration: Duration(milliseconds: 1500),
          backBufferDuration: Duration(seconds: 10),
        ),
        darwinLoadControl: DarwinLoadControl(
          automaticallyWaitsToMinimizeStalling: false,
          preferredForwardBufferDuration: Duration(seconds: 2),
        ),
      ),
      audioPipeline: AudioPipeline(
        androidAudioEffects: [
          _equalizer,
        ],
      ),
    );
    _initAudioStreams();
    _initAudioSession();
  }

  Future<void> _initAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());

      session.becomingNoisyEventStream.listen((_) {
        debugPrint('Audio output became noisy (headphones unplugged). Auto-pausing...');
        pause();
      });

      session.interruptionEventStream.listen((event) {
        if (event.begin) {
          _wasPlayingBeforeInterrupt = _player.playing;
          switch (event.type) {
            case AudioInterruptionType.duck:
              _preDuckVolume = _player.volume;
              _player.setVolume(0.35);
              break;
            case AudioInterruptionType.pause:
            case AudioInterruptionType.unknown:
              pause();
              break;
          }
        } else {
          switch (event.type) {
            case AudioInterruptionType.duck:
              _player.setVolume(_preDuckVolume);
              break;
            case AudioInterruptionType.pause:
              if (_wasPlayingBeforeInterrupt) play();
              break;
            case AudioInterruptionType.unknown:
              break;
          }
        }
      });
    } catch (e) {
      debugPrint('AudioSession initialization error: $e');
    }
  }

  AudioPlayer get player => _player;
  Song? get currentSong => _currentSong;
  AndroidEqualizer get equalizer => _equalizer;
  AndroidLoudnessEnhancer get loudnessEnhancer => _loudnessEnhancer;

  void setNavigationCallbacks({
    AsyncCallback? onSkipNext,
    AsyncCallback? onSkipPrevious,
    AsyncCallback? onCompleted,
    ValueChanged<Song>? onPlaybackFailed,
  }) {
    _onSkipNext = onSkipNext;
    _onSkipPrevious = onSkipPrevious;
    _onCompleted = onCompleted;
    _onPlaybackFailed = onPlaybackFailed;
  }

  void _initAudioStreams() {
    // Broadcast playback state changes
    _player.playbackEventStream.listen((PlaybackEvent event) {
      final playing = _player.playing;
      playbackState.add(
        playbackState.value.copyWith(
          controls: [
            MediaControl.skipToPrevious,
            if (playing) MediaControl.pause else MediaControl.play,
            MediaControl.stop,
            MediaControl.skipToNext,
          ],
          systemActions: const {
            MediaAction.seek,
            MediaAction.seekForward,
            MediaAction.seekBackward,
          },
          androidCompactActionIndices: const [0, 1, 3],
          processingState: const {
            ProcessingState.idle: AudioProcessingState.idle,
            ProcessingState.loading: AudioProcessingState.loading,
            ProcessingState.buffering: AudioProcessingState.buffering,
            ProcessingState.ready: AudioProcessingState.ready,
            ProcessingState.completed: AudioProcessingState.completed,
          }[_player.processingState] ?? AudioProcessingState.idle,
          playing: playing,
          updatePosition: _player.position,
          bufferedPosition: _player.bufferedPosition,
          speed: _player.speed,
          queueIndex: event.currentIndex,
        ),
      );
    });

    // Synchronize mediaItem duration dynamically when ExoPlayer resolves stream duration
    _player.durationStream.listen((dur) {
      if (dur != null && mediaItem.value != null && mediaItem.value!.duration != dur) {
        mediaItem.add(mediaItem.value!.copyWith(duration: dur));
      }
    });

    // Auto-advance when song finishes (guarded to fire only when track genuinely started and completed playback)
    _player.playerStateStream.listen((state) {
      LogService.instance.recordExoState('${state.processingState.name} (playing: ${state.playing})');
      if (state.playing && state.processingState == ProcessingState.ready) {
        _currentTrackActive = true;
        _completionHandled = false;
      }

      if (state.processingState == ProcessingState.completed && _currentTrackActive && !_completionHandled) {
        final total = _player.duration;
        final pos = _player.position;
        // Verify track genuinely played near completion (> 85% or within 4s of end)
        // If total is null or <= 5 seconds, this is a decode/network failure, NOT a genuine completion!
        if (total == null || total.inSeconds <= 5) {
          debugPrint('[AudioHandler] Incomplete track playback completion ignored (pos: ${pos.inSeconds}s, total: ${total?.inSeconds}s)');
          return;
        }
        final isNearEnd = pos.inSeconds >= (total.inSeconds - 4) || (total.inMilliseconds > 0 && (pos.inMilliseconds / total.inMilliseconds) >= 0.85);
        if (!isNearEnd) {
          debugPrint('[AudioHandler] Premature completion event detected (pos: ${pos.inSeconds}s, total: ${total.inSeconds}s)');
          _currentTrackActive = false;
          _completionHandled = true;
          if (_currentSong != null) {
            _onPlaybackFailed?.call(_currentSong!);
          }
          return;
        }
        _currentTrackActive = false;
        _completionHandled = true;
        debugPrint('[AudioHandler] Track "${_currentSong?.title}" completed playback cleanly. Invoking onCompleted.');
        _onCompleted?.call().catchError((e) {
          debugPrint('[AudioHandler] Error in _onCompleted callback: $e');
        });
      }
    });

    // SponsorBlock: auto-skip promotional/intro segments during YouTube playback
    _player.positionStream.listen((pos) {
      if (_activeSponsorSegments.isNotEmpty && !_isSkippingSponsor) {
        final currentSec = pos.inMilliseconds / 1000.0;
        final totalSec = (_player.duration?.inMilliseconds ?? 0) / 1000.0;
        // Never seek in the first 12 seconds to prevent stalling initial playback
        if (currentSec < 12.0) return;
        for (final segment in _activeSponsorSegments) {
          // Never skip near the very end of the song (prevents premature track completion)
          if (totalSec > 20.0 && segment.end >= (totalSec - 4.0)) continue;
          if (segment.end <= segment.start) continue;
          
          final segmentKey = '${segment.start.toStringAsFixed(1)}_${segment.end.toStringAsFixed(1)}';
          if (_skippedSegmentKeys.contains(segmentKey)) continue;

          if (currentSec >= segment.start && currentSec < (segment.end - 0.3)) {
            _isSkippingSponsor = true;
            _skippedSegmentKeys.add(segmentKey);
            debugPrint('SponsorBlock: auto-skipping ${segment.category} [${segment.start}s - ${segment.end}s]');
            final seekTarget = Duration(milliseconds: (segment.end * 1000).toInt() + 150);
            _player.seek(seekTarget).then((_) {
              _isSkippingSponsor = false;
            }).catchError((_) {
              _isSkippingSponsor = false;
            });
            break;
          }
        }
      }
    });
  }

  Future<void> playSong(Song song) async {
    // Reset flags immediately BEFORE touching ExoPlayer so state transitions during stop() cannot fire _onCompleted
    _currentTrackActive = false;
    _completionHandled = true;
    _currentSong = song;
    _activeSponsorSegments = [];
    _isSkippingSponsor = false;

    // Flush ExoPlayer pipeline before loading new track to avoid stale playback events
    try {
      await _player.stop();
    } catch (_) {}

    // Query SponsorBlock skip segments deferred (after 3s) so initial audio gets 100% bandwidth
    Future.delayed(const Duration(seconds: 3), () {
      if (_currentSong?.id != song.id) return;
      String? ytVideoId;
      if (song.id.startsWith('yt_')) {
        ytVideoId = song.id.substring(3);
      } else {
        ytVideoId = YouTubeImporterService.extractVideoId(song.streamUrl);
      }
      if (ytVideoId != null && ytVideoId.isNotEmpty) {
        SponsorBlockService.instance.getSkipSegments(ytVideoId).then((segments) {
          if (_currentSong?.id == song.id) {
            _activeSponsorSegments = segments;
            if (segments.isNotEmpty) {
              debugPrint('SponsorBlock: Loaded ${segments.length} skip segments for YouTube video $ytVideoId');
            }
          }
        }).catchError((_) {});
      }
    });
    mediaItem.add(
      MediaItem(
        id: song.id,
        album: 'Ember',
        title: song.title,
        artist: song.artist,
        duration: song.duration,
        artUri: song.artworkUrl.isNotEmpty ? Uri.tryParse(song.artworkUrl) : null,
      ),
    );

    // Immediately signal loading + playing state so UI and notification show active playing state
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          MediaControl.pause,
          MediaControl.stop,
          MediaControl.skipToNext,
        ],
        processingState: AudioProcessingState.loading,
        playing: true,
        updatePosition: Duration.zero,
        bufferedPosition: Duration.zero,
      ),
    );

    try {
      final s = song.streamUrl;
      final isLocal = s.startsWith('/') || s.startsWith('file://') || RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(s);

      if (isLocal) {
        var localPath = s.replaceFirst('file://', '');
        if (Platform.isWindows && localPath.startsWith('/') && localPath.length > 2 && localPath[2] == ':') {
          localPath = localPath.substring(1);
        }
        final file = File(localPath);
        if (await file.exists()) {
          await _player.setFilePath(localPath, initialPosition: Duration.zero, preload: true);
          if (_currentSong?.id != song.id) return;
          await _player.play();
          return;
        } else {
          // File does not exist locally anymore; fall through to online stream resolver
          LogService.w('AudioHandler', 'Local file not found at $localPath, falling through to online resolver');
        }
      }

      // Online pure YouTube stream resolution via NewPipe extractor
      final targetSong = song;
      LogService.instance.recordActiveTrack(song);

      // Resolve direct YouTube Opus / AAC streams
      final candidates = await StreamResolverService.resolvePlayableStreamCandidates(song);
      if (_currentSong?.id != targetSong.id) return; // Superseded by newer track selection
      if (candidates.isEmpty && s.isNotEmpty && !s.contains('youtube.com/watch') && !s.contains('youtu.be/')) {
        candidates.add(s);
      }
      LogService.instance.recordCandidates(candidates);

      bool started = false;
      for (int i = 0; i < candidates.length; i++) {
        if (_currentSong?.id != targetSong.id) return; // Superseded by newer track selection
        final url = candidates[i];
        if (url.isEmpty || url.contains('youtube.com/watch') || url.contains('youtu.be/')) continue;
        final isYouTubeStream = url.contains('googlevideo.com') || url.contains('youtube.com');

        // Attempt 1: Standard YouTube streaming headers (Origin, Referer, Firefox User-Agent)
        try {
          LogService.stream('AudioHandler', 'Connecting to candidate #${i + 1} with YouTube streaming headers...');
          await _player.setUrl(
            url,
            headers: isYouTubeStream ? _youtubeHeaders : null,
            initialPosition: Duration.zero,
            preload: true,
          ).timeout(const Duration(seconds: 5));
          if (_currentSong?.id != targetSong.id) return;
          await _player.play();
          started = true;
          LogService.instance.recordPlaybackSuccess(song);
          debugPrint('Successfully playing "${song.title}" via candidate #${i + 1}');
          break;
        } catch (e) {
          LogService.w('AudioHandler', 'Candidate #${i + 1} with headers failed: $e. Retrying raw...');
        }

        // Attempt 2: Standard setUrl without headers (quick 3s fallback)
        if (_currentSong?.id == targetSong.id) {
          try {
            await _player.setUrl(
              url,
              initialPosition: Duration.zero,
              preload: true,
            ).timeout(const Duration(seconds: 3));
            if (_currentSong?.id != targetSong.id) return;
            await _player.play();
            started = true;
            LogService.instance.recordPlaybackSuccess(song);
            debugPrint('Successfully playing "${song.title}" via candidate #${i + 1} raw stream');
            break;
          } catch (e) {
            LogService.w('AudioHandler', 'Candidate #${i + 1} raw stream failed: $e. Moving to next candidate...');
          }
        }
      }

      // Tier 2 Fallback: If all direct YouTube candidate streams fail, try Piped audio proxy
      if (!started && _currentSong?.id == targetSong.id) {
        final videoId = song.id.startsWith('yt_')
            ? song.id.replaceFirst('yt_', '')
            : YouTubeImporterService.extractVideoId(song.streamUrl);
        if (videoId != null && videoId.isNotEmpty) {
          try {
            LogService.stream('AudioHandler', 'Direct streams failed, attempting Piped proxy fallback for $videoId...');
            final pipedUrl = await PipedService.getAudioStream(videoId);
            if (pipedUrl != null && pipedUrl.isNotEmpty && _currentSong?.id == targetSong.id) {
              await _player.setUrl(
                pipedUrl,
                headers: _youtubeHeaders,
                initialPosition: Duration.zero,
                preload: true,
              ).timeout(const Duration(seconds: 10));
              if (_currentSong?.id != targetSong.id) return;
              await _player.play();
              started = true;
              LogService.instance.recordPlaybackSuccess(song);
              debugPrint('Successfully playing "${song.title}" via Piped proxy fallback');
            }
          } catch (e) {
            LogService.w('AudioHandler', 'Piped proxy fallback error: $e');
            debugPrint('[AudioHandler] Piped proxy fallback error for "${song.title}": $e');
          }
        }
      }

      if (!started) {
        if (_currentSong?.id != targetSong.id) return; // Superseded by newer track selection
        debugPrint('All stream candidates failed for "${song.title}". Halting playback gracefully.');
        LogService.instance.recordPlaybackFailure(song, 'All stream candidates exhausted (failed to connect or decode audio)');
        StreamResolverService.invalidateCache(song.id);
        YouTubeImporterService.invalidateCache(song.id);
        playbackState.add(
          playbackState.value.copyWith(
            processingState: AudioProcessingState.idle,
            playing: false,
          ),
        );
        _onPlaybackFailed?.call(song);
        return;
      }
    } catch (e, st) {
      if (_currentSong?.id != song.id) return; // Superseded by newer track selection
      debugPrint('Playback error: $e');
      LogService.instance.recordPlaybackFailure(song, e, st);
      StreamResolverService.invalidateCache(song.id);
      YouTubeImporterService.invalidateCache(song.id);
      playbackState.add(
        playbackState.value.copyWith(
          processingState: AudioProcessingState.idle,
          playing: false,
        ),
      );
      _onPlaybackFailed?.call(song);
    }
  }

  // Equalizer & Audio Shaping Controls (Pure Hardware Multi-Band DSP, No Artificial Gain Blowout)
  Future<void> _updateAudioEffects() async {
    try {
      await _equalizer.setEnabled(_eqEnabled);
    } catch (e) {
      debugPrint('Error updating equalizer enabled state: $e');
    }
  }

  Future<void> setEqualizerEnabled(bool enabled) async {
    _eqEnabled = enabled;
    await _updateAudioEffects();
    if (_eqEnabled) {
      await applyEqualizerPreset(_currentPreset);
    }
  }

  Future<void> setBassBoost(double gain) async {
    _bassBoost = gain.clamp(0.0, 1.0);
    if (_eqEnabled) {
      await applyEqualizerPreset(_currentPreset);
    }
  }

  Future<void> setBandGain(int bandIndex, double gain) async {
    try {
      final params = await _equalizer.parameters;
      if (bandIndex >= 0 && bandIndex < params.bands.length) {
        final clamped = gain.clamp(params.minDecibels, params.maxDecibels);
        await params.bands[bandIndex].setGain(clamped);
      }
    } catch (_) {}
  }

  Future<void> applyEqualizerPreset(String preset) async {
    _currentPreset = preset;
    try {
      final params = await _equalizer.parameters;
      final bands = params.bands;
      final n = bands.length;
      if (n == 0) return;

      final minDb = params.minDecibels;
      final maxDb = params.maxDecibels;
      double clampGain(double g) => g.clamp(minDb, maxDb);

      // Clean, musical low-end boost without digital distortion or ear-splitting gain multiplication
      final bassAdd = _bassBoost * 3.5;
      final lowMidAdd = _bassBoost * 1.5;

      switch (preset) {
        case 'Warm Tape':
          // Subtle analog warmth: smooth low-end, neutral mids, soft treble roll-off
          for (int i = 0; i < n; i++) {
            if (i == 0) {
              await bands[i].setGain(clampGain(1.5 + bassAdd));
            } else if (i == 1) {
              await bands[i].setGain(clampGain(0.8 + lowMidAdd));
            } else if (i == n - 1) {
              await bands[i].setGain(clampGain(-0.5));
            } else {
              await bands[i].setGain(clampGain(0.0));
            }
          }
          break;
        case 'Lo-Fi':
          // Warm vinyl mids, rolled-off extreme bass and highs
          for (int i = 0; i < n; i++) {
            if (i == 0) {
              await bands[i].setGain(clampGain(0.0 + bassAdd));
            } else if (i == 1 || i == 2) {
              await bands[i].setGain(clampGain(1.5));
            } else if (i >= n - 2) {
              await bands[i].setGain(clampGain(-1.0));
            } else {
              await bands[i].setGain(clampGain(0.5));
            }
          }
          break;
        case 'Bass Boost':
          // Focused low-frequency punch with zero volume blowout
          for (int i = 0; i < n; i++) {
            if (i == 0) {
              await bands[i].setGain(clampGain(3.0 + bassAdd));
            } else if (i == 1) {
              await bands[i].setGain(clampGain(1.5 + lowMidAdd));
            } else {
              await bands[i].setGain(clampGain(0.0));
            }
          }
          break;
        case 'Vocal Air':
          // Clear vocals and upper presence
          for (int i = 0; i < n; i++) {
            if (i == 0) {
              await bands[i].setGain(clampGain(0.0 + bassAdd));
            } else if (i >= n - 2) {
              await bands[i].setGain(clampGain(2.0));
            } else {
              await bands[i].setGain(clampGain(0.8));
            }
          }
          break;
        case 'Acoustic':
          // Clean acoustic resonance
          for (int i = 0; i < n; i++) {
            if (i == 0) {
              await bands[i].setGain(clampGain(1.0 + bassAdd));
            } else if (i == n - 1) {
              await bands[i].setGain(clampGain(1.2));
            } else {
              await bands[i].setGain(clampGain(0.4));
            }
          }
          break;
        case 'Flat':
        default:
          for (int i = 0; i < n; i++) {
            if (i == 0) {
              await bands[i].setGain(clampGain(bassAdd));
            } else if (i == 1) {
              await bands[i].setGain(clampGain(lowMidAdd));
            } else {
              await bands[i].setGain(clampGain(0.0));
            }
          }
          break;
      }
    } catch (e) {
      debugPrint('Apply preset error: $e');
    }
  }

  @override
  Future<void> skipToNext() async {
    if (_onSkipNext != null) {
      await _onSkipNext!();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_onSkipPrevious != null) {
      await _onSkipPrevious!();
    }
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<void> stop() async {
    _currentSong = null;
    _currentTrackActive = false;
    _completionHandled = true;
    _isSkippingSponsor = false;
    _activeSponsorSegments = [];
    _skippedSegmentKeys.clear();
    mediaItem.add(null);
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.idle,
        playing: false,
      ),
    );
    await _player.stop();
    await super.stop();
  }

}
