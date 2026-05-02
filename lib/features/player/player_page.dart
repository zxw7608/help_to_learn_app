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
    final info = app_main.audioService.playbackInfo.value;

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
      body: LayoutBuilder(
        builder: (ctx, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 20),
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
                  const SizedBox(height: 24),
                  // Segment text
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
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (info.subtitle.isNotEmpty)
                          Text(
                            info.subtitle,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 14, color: Colors.white54),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Seek bar + nav row (own listener, only these rebuild on position ticks)
                  _PlayerControls(
                    info: info,
                    playlist: playlist,
                    onPrevMaterial: () => app_main.audioService.onPlaylistNav?.call(false),
                    onNextMaterial: () => app_main.audioService.onPlaylistNav?.call(true),
                  ),
                  const SizedBox(height: 10),
                  // Mode & speed toggle buttons
                  _ModeButtons(playlist: playlist, info: info),
                  const SizedBox(height: 8),
                  // Playlist queue peek
                  if (playlist.isNotEmpty && playlist.hasCurrent)
                    _QueuePeek(playlist: playlist),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Player Controls (listens to position) ────────────────────────────────────

class _PlayerControls extends StatefulWidget {
  final PlaybackInfo info;
  final PlaylistState playlist;
  final VoidCallback onPrevMaterial;
  final VoidCallback onNextMaterial;

  const _PlayerControls({
    required this.info,
    required this.playlist,
    required this.onPrevMaterial,
    required this.onNextMaterial,
  });

  @override
  State<_PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends State<_PlayerControls> {
  double _sliderValue = 0.0;
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PlaybackInfo>(
      valueListenable: app_main.audioService.playbackInfo,
      builder: (ctx, info, _) {
        final durationMs = info.duration?.inMilliseconds ?? 0;
        if (!_isDragging && durationMs > 0) {
          _sliderValue = (info.position.inMilliseconds / durationMs).clamp(0.0, 1.0);
        }

        return Column(
          children: [
            // Seek slider
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  Slider(
                    value: _sliderValue,
                    onChanged: durationMs > 0
                        ? (v) {
                            _sliderValue = v;
                            _isDragging = true;
                          }
                        : null,
                    onChangeEnd: durationMs > 0
                        ? (v) {
                            _isDragging = false;
                            final target = Duration(
                                milliseconds: (v * durationMs).round());
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
                            style: const TextStyle(fontSize: 12, color: Colors.white54)),
                        Text(
                            info.duration != null ? _formatDuration(info.duration!) : '--:--',
                            style: const TextStyle(fontSize: 12, color: Colors.white54)),
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
              playlist: widget.playlist,
              onPrevMaterial: info.hasPrevPlaylist ? widget.onPrevMaterial : null,
              onNextMaterial: info.hasNextPlaylist ? widget.onNextMaterial : null,
            ),
          ],
        );
      },
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
                style: const TextStyle(fontSize: 12, color: Colors.white70),
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
                  style: const TextStyle(fontSize: 11, color: Colors.white60),
                ),
              ),
              const SizedBox(height: 2),
              const Icon(Icons.open_in_new, size: 14, color: Colors.white38),
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

  const _NavRow({
    required this.info,
    required this.playlist,
    this.onPrevMaterial,
    this.onNextMaterial,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          iconSize: 32,
          icon: const Icon(Icons.skip_previous),
          tooltip: '上一个素材',
          onPressed: info.hasPrevPlaylist ? onPrevMaterial : null,
        ),
        const SizedBox(width: 4),
        IconButton(
          iconSize: 28,
          icon: const Icon(Icons.fast_rewind),
          tooltip: '上一个片段',
          onPressed: info.hasPrevSegment
              ? () => app_main.audioService.previousSegment()
              : null,
        ),
        const SizedBox(width: 8),
        _PlayButton(playing: info.playing, playlist: playlist),
        const SizedBox(width: 8),
        IconButton(
          iconSize: 28,
          icon: const Icon(Icons.fast_forward),
          tooltip: '下一个片段',
          onPressed: info.hasNextSegment
              ? () => app_main.audioService.nextSegment()
              : null,
        ),
        const SizedBox(width: 4),
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

class _PlayButton extends ConsumerWidget {
  final bool playing;
  final PlaylistState playlist;
  const _PlayButton({required this.playing, required this.playlist});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () {
        if (playing) {
          app_main.audioService.pause();
        } else if (app_main.audioService.playbackInfo.value.currentMaterialId == 0) {
          ref.read(playlistManagerProvider.notifier).playFromCurrent();
        } else {
          app_main.audioService.play();
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
              color: Theme.of(context).colorScheme.primary.withOpacity(0.4),
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

// ─── Mode & Speed Buttons ─────────────────────────────────────────────────────

class _ModeButtons extends ConsumerWidget {
  final PlaylistState playlist;
  final PlaybackInfo info;
  const _ModeButtons({required this.playlist, required this.info});

  static const _speeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  String get _speedLabel {
    final s = info.speed;
    if (s == 1.0) return '1×';
    return '$s×';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final notifier = ref.read(playlistManagerProvider.notifier);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          _ToggleChip(
            label: '素材',
            value: playlist.materialMode.shortLabel,
            onTap: () => notifier.cycleMaterialMode(),
            cs: cs,
          ),
          const SizedBox(width: 6),
          _ToggleChip(
            label: '片段',
            value: playlist.segmentMode.shortLabel,
            onTap: () => notifier.cycleSegmentMode(),
            cs: cs,
          ),
          const SizedBox(width: 6),
          _ToggleChip(
            label: '循环',
            value: playlist.playlistLoop ? '开' : '关',
            onTap: () => notifier.togglePlaylistLoop(),
            cs: cs,
            active: playlist.playlistLoop,
          ),
          const SizedBox(width: 6),
          _ToggleChip(
            label: '速度',
            value: _speedLabel,
            onTap: () {
              final curIdx = _speeds.indexWhere((s) => (info.speed - s).abs() < 0.01);
              final nextIdx = curIdx < 0 ? 3 : (curIdx + 1) % _speeds.length;
              app_main.audioService.setSpeed(_speeds[nextIdx]);
            },
            cs: cs,
          ),
        ],
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;
  final ColorScheme cs;
  final bool active;

  const _ToggleChip({
    required this.label,
    required this.value,
    required this.onTap,
    required this.cs,
    this.active = true,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? cs.primary.withOpacity(0.15) : Colors.white10,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active ? cs.primary.withOpacity(0.3) : Colors.white12,
            ),
          ),
          child: Column(
            children: [
              Text(value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: active ? Colors.white : Colors.white38,
                  )),
              const SizedBox(height: 2),
              Text(label,
                  style: const TextStyle(fontSize: 10, color: Colors.white54)),
            ],
          ),
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
