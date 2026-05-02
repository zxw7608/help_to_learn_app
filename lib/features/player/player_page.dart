import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import '../../main.dart' as app_main;
import '../../core/services/audio_handler.dart';

/// Minimal player page shown as a full-screen overlay.
class PlayerPage extends StatelessWidget {
  const PlayerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('正在播放'),
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<MediaItem?>(
        stream: (app_main.audioHandler as HelpToLearnAudioHandler).mediaItem,
        builder: (ctx, snapshot) {
          final item = snapshot.data;
          return Column(
            children: [
              const Spacer(),
              // Album art placeholder
              Container(
                width: 220,
                height: 220,
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
                child: const Icon(Icons.headphones, size: 80, color: Colors.white),
              ),
              const SizedBox(height: 32),
              // Track info
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: [
                    Text(
                      item?.title ?? '加载中...',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    if (item?.artist != null && item!.artist!.isNotEmpty)
                      Text(
                        item.artist!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 14, color: Colors.white54),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              // Position slider
              StreamBuilder<PlaybackState>(
                stream: app_main.audioHandler.playbackState,
                builder: (ctx, snapshot) {
                  final state = snapshot.data;
                  final position = state?.position ?? Duration.zero;
                  final duration = (app_main.audioHandler as HelpToLearnAudioHandler)
                      .mediaItem.value?.duration;

                  return Column(
                    children: [
                      Slider(
                        value: duration != null && duration.inMilliseconds > 0
                            ? (position.inMilliseconds /
                                    duration.inMilliseconds)
                                .clamp(0.0, 1.0)
                            : 0.0,
                        onChanged: duration != null
                            ? (v) {
                                final target = Duration(
                                    milliseconds:
                                        (v * duration.inMilliseconds).round());
                                app_main.audioHandler.seek(target);
                              }
                            : null,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_formatDuration(position),
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.white54)),
                            Text(
                                duration != null
                                    ? _formatDuration(duration)
                                    : '--:--',
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.white54)),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              // Controls row
              StreamBuilder<PlaybackState>(
                stream: app_main.audioHandler.playbackState,
                builder: (ctx, snapshot) {
                  final playing = snapshot.data?.playing ?? false;
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        iconSize: 32,
                        icon: const Icon(Icons.skip_previous),
                        onPressed: () =>
                            app_main.audioHandler.skipToPrevious(),
                      ),
                      const SizedBox(width: 8),
                      _BigPlayButton(playing: playing),
                      const SizedBox(width: 8),
                      IconButton(
                        iconSize: 32,
                        icon: const Icon(Icons.skip_next),
                        onPressed: () => app_main.audioHandler.skipToNext(),
                      ),
                    ],
                  );
                },
              ),
              const Spacer(),
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

class _BigPlayButton extends StatelessWidget {
  final bool playing;
  const _BigPlayButton({required this.playing});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (playing) {
          app_main.audioHandler.pause();
        } else {
          app_main.audioHandler.play();
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
