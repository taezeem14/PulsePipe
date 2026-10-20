import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../providers/player_provider.dart';
import '../theme/ember_theme.dart';

class SynchronizedLyricsView extends StatefulWidget {
  const SynchronizedLyricsView({super.key});

  @override
  State<SynchronizedLyricsView> createState() => _SynchronizedLyricsViewState();
}

class _SynchronizedLyricsViewState extends State<SynchronizedLyricsView> {
  final ScrollController _scrollController = ScrollController();
  int _lastIndex = -1;
  bool _userScrolling = false;
  Timer? _userScrollTimer;

  String? _currentSongId;

  @override
  void dispose() {
    _userScrollTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToIndex(int index, int totalLines) {
    if (!_scrollController.hasClients ||
        !_scrollController.position.hasContentDimensions ||
        _userScrolling ||
        index < 0 ||
        index >= totalLines) {
      return;
    }

    const lineEstimate = 56.0;
    // With viewport-centered padding, offset of line index is index * lineEstimate
    final targetOffset = index * lineEstimate;
    final clamped = targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent);

    _scrollController.animateTo(
      clamped,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final cur = player.currentSong;

    if (cur != null && cur.id != _currentSongId) {
      _currentSongId = cur.id;
      _lastIndex = -1;
      _userScrolling = false;
    }

    if (cur == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FaIcon(FontAwesomeIcons.music, size: 32, color: EmberColors.textMuted),
            SizedBox(height: 12),
            Text('No song playing', style: TextStyle(color: EmberColors.textMuted)),
          ],
        ),
      );
    }

    if (player.isLoadingLyrics) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: EmberColors.primaryAmber,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Finding lyrics for ${cur.title}...',
              style: const TextStyle(color: EmberColors.textSecondary, fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );
    }

    final synced = player.syncedLyrics;
    final hasSynced = player.hasSyncedLyrics;
    final plain = player.plainLyrics;

    if (hasSynced && synced.isNotEmpty) {
      final activeIdx = player.currentLyricIndex;

      if (activeIdx != _lastIndex && activeIdx >= 0) {
        _lastIndex = activeIdx;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _scrollToIndex(activeIdx, synced.length);
          }
        });
      }

      return LayoutBuilder(
        builder: (context, constraints) {
          final verticalCenterPadding = (constraints.maxHeight / 2) - 28.0;
          final safeVerticalPadding = verticalCenterPadding.clamp(24.0, 500.0);

          return NotificationListener<UserScrollNotification>(
            onNotification: (notif) {
              if (notif.direction != ScrollDirection.idle) {
                _userScrolling = true;
                _userScrollTimer?.cancel();
              } else {
                _userScrollTimer?.cancel();
                _userScrollTimer = Timer(const Duration(seconds: 3), () {
                  if (mounted) _userScrolling = false;
                });
              }
              return false;
            },
            child: ListView.builder(
              controller: _scrollController,
              padding: EdgeInsets.symmetric(
                horizontal: 20,
                vertical: safeVerticalPadding,
              ),
              itemCount: synced.length,
              itemBuilder: (context, index) {
                final line = synced[index];
                final isActive = index == activeIdx;

                if (line.text.trim().isEmpty) {
                  return const SizedBox(height: 16);
                }

                return Center(
                  child: GestureDetector(
                    onTap: () {
                      player.seek(line.timestamp);
                      _userScrolling = false;
                      _scrollToIndex(index, synced.length);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: isActive
                            ? EmberColors.primaryAmber.withValues(alpha: 0.16)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                        border: isActive
                            ? Border.all(color: EmberColors.primaryAmber.withValues(alpha: 0.35), width: 1.2)
                            : null,
                      ),
                      child: Text(
                        line.text,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: isActive
                              ? EmberColors.primaryAmberHi
                              : EmberColors.textPrimary.withValues(alpha: 0.4),
                          fontSize: isActive ? 18 : 15,
                          fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                          height: 1.5,
                          letterSpacing: isActive ? 0.3 : 0.0,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      );
    }

    if (plain.trim().isNotEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        child: SelectableText(
          plain,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: EmberColors.textPrimary,
            fontSize: 16,
            height: 2.0,
            letterSpacing: 0.3,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const FaIcon(FontAwesomeIcons.alignLeft, size: 36, color: EmberColors.textMuted),
          const SizedBox(height: 12),
          const Text(
            'Instrumental / No lyrics available',
            style: TextStyle(color: EmberColors.textMuted, fontSize: 14),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: () => player.retryFetchLyrics(),
            icon: const FaIcon(FontAwesomeIcons.arrowsRotate, size: 14, color: EmberColors.primaryAmber),
            label: const Text('Search Again', style: TextStyle(color: EmberColors.primaryAmber)),
          ),
        ],
      ),
    );
  }
}
