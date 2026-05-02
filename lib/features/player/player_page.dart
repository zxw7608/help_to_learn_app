import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../main.dart' as app_main;
import '../../core/services/custom_audio_service.dart';
import '../../core/services/playlist_manager.dart';
import '../../core/models/playlist.dart';

class PlayerPage extends ConsumerWidget {
  const PlayerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlist = ref.watch(playlistManagerProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('正在播放'),
            if (playlist.isNotEmpty && playlist.hasCurrent)
              Text(
                playlist.current!.title,
                style: const TextStyle(fontSize: 13, color: Colors.white60),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (playlist.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.queue_music_outlined, size: 22),
              tooltip: '播放列表',
              onPressed: () => context.go('/playlist'),
            ),
        ],
      ),
      body: ValueListenableBuilder<PlaybackInfo>(
        valueListenable: app_main.audioService.playbackInfo,
        builder: (ctx, info, _) {
          return Column(
            children: [
              const Spacer(flex: 1),
              // Album art + material info
              _AlbumArt(
                info: info,
                playlist: playlist,
                onTapMaterial: () {
                  if (info.currentMaterialId > 0) {
                    GoRouter.of(context).push('/material/${info.currentMaterialId}');
                  }
                },
              ),
              const SizedBox(height: 28),
              // Segment text — tap to go to material detail
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: info.currentMaterialId > 0
                          ? () => GoRouter.of(context).push('/material/${info.currentMaterialId}')
                          : null,
                      child: Text(
                        info.title.isNotEmpty ? info.title : '加载中...',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w600),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (info.subtitle.isNotEmpty)
                      Text(
                        info.subtitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 14, color: Colors.white54),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Seek slider
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  children: [
                    Slider(
                      value: info.duration != null &&
                              info.duration!.inMilliseconds > 0
                          ? (info.position.inMilliseconds /
                                  info.duration!.inMilliseconds)
                              .clamp(0.0, 1.0)
                          : 0.0,
                      onChanged: info.duration != null
                          ? (v) {
                              final target = Duration(
                                  milliseconds: (v *
                                          info.duration!.inMilliseconds)
                                      .round());
                              app_main.audioService.seek(target);
                            }
                          : null,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_formatDuration(info.position),
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.white54)),
                          Text(
                              info.duration != null
                                  ? _formatDuration(info.duration!)
                                  : '--:--',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.white54)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Navigation row
              _NavRow(
                info: info,
                playlist: playlist,
                onPrevMaterial: info.hasPrevPlaylist
                    ? () => app_main.audioService.onPlaylistNav?.call(false)
                    : null,
                onNextMaterial: info.hasNextPlaylist
                    ? () => app_main.audioService.onPlaylistNav?.call(true)
                    : null,
                onPlay: () {
                  if (info.title.isEmpty && playlist.isNotEmpty) {
                    ref
                        .read(playlistManagerProvider.notifier)
                        .playFromCurrent();
                  } else {
                    app_main.audioService.play();
                  }
                },
              ),
              const SizedBox(height: 10),
              // Mode indicator
              if (info.playModeLabel.isNotEmpty)
                _ModeBar(
                  info: info,
                  playlist: playlist,
                  onCycleMode: () =>
                      ref.read(playlistManagerProvider.notifier).cycleMaterialMode(),
                ),
              const SizedBox(height: 12),
              // Playlist queue peek
              if (playlist.isNotEmpty && playlist.hasCurrent)
                _QueuePeek(playlist: playlist),
              const Spacer(flex: 1),
            ],
          );
        },
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

// ─── Album Art ──────────────────────────────────────────────────────────────

class _AlbumArt extends StatelessWidget {
  final PlaybackInfo info;
  final PlaylistState playlist;
  final VoidCallback onTapMaterial;

  const _AlbumArt({
    required this.info,
    required this.playlist,
    required this.onTapMaterial,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: info.currentMaterialId > 0 ? onTapMaterial : null,
      child: Container(
        width: 200,
        height: 200,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Theme.of(context).colorScheme.primary.withOpacity(0.8),
              Theme.of(context).colorScheme.secondary.withOpacity(0.6),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.headphones, size: 56, color: Colors.white),
            if (info.playlistInfo.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                info.playlistInfo,
                style: const TextStyle(
                    fontSize: 12, color: Colors.white70),
              ),
            ],
            if (info.materialTitle.isNotEmpty) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  info.materialTitle,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11, color: Colors.white60),
                ),
              ),
              const SizedBox(height: 2),
              const Icon(Icons.open_in_new,
                  size: 14, color: Colors.white38),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Navigation Row ─────────────────────────────────────────────────────────

class _NavRow extends StatelessWidget {
  final PlaybackInfo info;
  final PlaylistState playlist;
  final VoidCallback? onPrevMaterial;
  final VoidCallback? onNextMaterial;
  final VoidCallback? onPlay;

  const _NavRow({
    required this.info,
    required this.playlist,
    this.onPrevMaterial,
    this.onNextMaterial,
    this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Prev in playlist
        IconButton(
          iconSize: 32,
          icon: const Icon(Icons.skip_previous),
          tooltip: '上一个素材',
          onPressed: info.hasPrevPlaylist ? onPrevMaterial : null,
        ),
        const SizedBox(width: 4),
        // Prev segment
        IconButton(
          iconSize: 28,
          icon: const Icon(Icons.fast_rewind),
          tooltip: '上一个片段',
          onPressed: info.hasPrevSegment
              ? () => app_main.audioService.previousSegment()
              : null,
        ),
        const SizedBox(width: 8),
        // Play/Pause
        _BigPlayButton(playing: info.playing, onPlay: onPlay),
        const SizedBox(width: 8),
        // Next segment
        IconButton(
          iconSize: 28,
          icon: const Icon(Icons.fast_forward),
          tooltip: '下一个片段',
          onPressed: info.hasNextSegment
              ? () => app_main.audioService.nextSegment()
              : null,
        ),
        const SizedBox(width: 4),
        // Next in playlist
        IconButton(
          iconSize: 32,
          icon: const Icon(Icons.skip_next),
          tooltip: '下一个素材',
          onPressed: info.hasNextPlaylist ? onNextMaterial : null,
        ),
      ],
    );
  }
}

class _BigPlayButton extends StatelessWidget {
  final bool playing;
  final VoidCallback? onPlay;
  const _BigPlayButton({required this.playing, this.onPlay});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (playing) {
          app_main.audioService.pause();
        } else {
          onPlay?.call();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color:
                  Theme.of(context).colorScheme.primary.withOpacity(0.4),
              blurRadius: 20,
              spreadRadius: 4,
            ),
          ],
        ),
        child: Icon(
          playing ? Icons.pause : Icons.play_arrow,
          size: 36,
          color: Colors.white,
        ),
      ),
    );
  }
}

// ─── Mode Bar ───────────────────────────────────────────────────────────────

class _ModeBar extends StatelessWidget {
  final PlaybackInfo info;
  final PlaylistState playlist;
  final VoidCallback onCycleMode;

  const _ModeBar({
    required this.info,
    required this.playlist,
    required this.onCycleMode,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onCycleMode,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: cs.primary.withOpacity(0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.primary.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.shuffle_on, size: 16, color: Colors.white54),
            const SizedBox(width: 6),
            Text(
              '素材: ${playlist.materialMode.shortLabel} · 片段: ${playlist.segmentMode.shortLabel}${playlist.playlistLoop ? " · 循环" : ""}',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 14, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}

// ─── Queue Peek ─────────────────────────────────────────────────────────────

class _QueuePeek extends StatelessWidget {
  final PlaylistState playlist;
  const _QueuePeek({required this.playlist});

  @override
  Widget build(BuildContext context) {
    final entries = playlist.entries;
    final current = playlist.currentIndex;

    // Show up to 3 upcoming materials
    final upcoming = <int>[];
    for (int i = 1; i <= 3; i++) {
      final idx = (current + i) % entries.length;
      if (idx != current && idx < entries.length) {
        upcoming.add(idx);
      }
    }

    if (upcoming.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('即将播放',
              style: TextStyle(fontSize: 11, color: Colors.white38)),
          const SizedBox(height: 6),
          ...upcoming.map((i) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Center(
                        child: Text('${i + 1}',
                            style: const TextStyle(
                                fontSize: 10, color: Colors.white54)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        entries[i].title,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.white54),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
