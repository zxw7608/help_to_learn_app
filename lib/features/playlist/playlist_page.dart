import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/playlist_manager.dart';
import '../../core/services/custom_audio_service.dart';
import '../../core/models/playlist.dart';
import '../../main.dart' as app_main;

class PlaylistPage extends ConsumerStatefulWidget {
  const PlaylistPage({super.key});

  @override
  ConsumerState<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends ConsumerState<PlaylistPage> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playlistManagerProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('播放列表'),
            if (state.isNotEmpty)
              Text('${state.entries.length} 个素材',
                  style:
                      const TextStyle(fontSize: 12, color: Colors.white54)),
          ],
        ),
        actions: [
          if (state.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '清空列表',
              onPressed: () => _confirmClear(),
            ),
        ],
      ),
      body: state.isEmpty
          ? _buildEmpty()
          : Column(
              children: [
                Expanded(child: _buildList(state, cs)),
                if (state.hasCurrent)
                  _MiniPlayerBar(
                    state: state,
                    onPlayCurrent: () => ref
                        .read(playlistManagerProvider.notifier)
                        .playFromCurrent(),
                    onTapMode: () =>
                        ref.read(playlistManagerProvider.notifier).cycleMode(),
                  ),
              ],
            ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.queue_music_outlined, size: 72, color: Colors.white24),
          const SizedBox(height: 16),
          const Text('播放列表为空',
              style: TextStyle(fontSize: 18, color: Colors.white54)),
          const SizedBox(height: 8),
          const Text('从素材库添加素材到播放列表',
              style: TextStyle(fontSize: 14, color: Colors.white38)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => context.go('/materials'),
            icon: const Icon(Icons.library_books),
            label: const Text('前往素材库'),
          ),
        ],
      ),
    );
  }

  Widget _buildList(PlaylistState state, ColorScheme cs) {
    return ReorderableListView.builder(
      key: const PageStorageKey('playlist_reorderable'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      itemCount: state.entries.length,
      onReorder: (oldIdx, newIdx) {
        ref.read(playlistManagerProvider.notifier).reorder(
              oldIdx,
              newIdx,
            );
      },
      proxyDecorator: (child, index, animation) {
        return AnimatedBuilder(
          animation: animation,
          builder: (_, child) => Material(
            color: Colors.transparent,
            elevation: 4,
            child: child,
          ),
          child: child,
        );
      },
      itemBuilder: (ctx, i) {
        final entry = state.entries[i];
        final isCurrent = i == state.currentIndex;
        return _PlaylistCard(
          key: ValueKey(entry.materialId),
          entry: entry,
          index: i,
          isCurrent: isCurrent,
          isPlaying: isCurrent && _isPlaying(),
          onTap: () {
            ref.read(playlistManagerProvider.notifier).playAtIndex(i);
            _goToPlayer();
          },
          onDelete: () {
            ref.read(playlistManagerProvider.notifier).removeMaterialAt(i);
          },
        );
      },
    );
  }

  void _goToPlayer() {
    final router = GoRouter.of(context);
    if (router.state?.uri.toString() != '/player') {
      router.push('/player');
    }
  }

  bool _isPlaying() {
    return ref.watch(playlistManagerProvider).hasCurrent;
  }

  void _confirmClear() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('清空播放列表'),
        content: const Text('确定要清空播放列表吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(playlistManagerProvider.notifier).clear();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
            ),
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }
}

// ─── Playlist Card ───────────────────────────────────────────────────────────

class _PlaylistCard extends StatelessWidget {
  final PlaylistEntry entry;
  final int index;
  final bool isCurrent;
  final bool isPlaying;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _PlaylistCard({
    super.key,
    required this.entry,
    required this.index,
    required this.isCurrent,
    required this.isPlaying,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isCurrent ? cs.primary.withOpacity(0.6) : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
          child: Row(
            children: [
              // Drag handle
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.drag_handle, color: Colors.white24, size: 22),
                ),
              ),
              // Index / playing indicator
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isCurrent
                      ? cs.primary.withOpacity(0.25)
                      : Colors.white10,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: isPlaying
                      ? Icon(Icons.volume_up, size: 16, color: cs.primary)
                      : Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color:
                                isCurrent ? cs.primary : Colors.white54,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isCurrent ? Colors.white : const Color(0xDEFFFFFF),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _chip(entry.language.toUpperCase()),
                        const SizedBox(width: 6),
                        _chip(entry.status.name),
                      ],
                    ),
                  ],
                ),
              ),
              // Delete button
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: Colors.white38),
                onPressed: onDelete,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: const TextStyle(fontSize: 10, color: Colors.white54)),
    );
  }
}

// ─── Mini Player Bar ──────────────────────────────────────────────────────────

class _MiniPlayerBar extends StatelessWidget {
  final PlaylistState state;
  final VoidCallback onPlayCurrent;
  final VoidCallback onTapMode;
  const _MiniPlayerBar({required this.state, required this.onPlayCurrent, required this.onTapMode});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ValueListenableBuilder<PlaybackInfo>(
      valueListenable: app_main.audioService.playbackInfo,
      builder: (ctx, info, _) {
        final isPlaying = info.playing;
        final current = state.current;
        if (current == null) return const SizedBox.shrink();

        return GestureDetector(
          onTap: () {
            final router = GoRouter.of(context);
            if (router.state?.uri.toString() != '/player') {
              router.push('/player');
            }
          },
          child: Container(
            height: 56,
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.primary.withOpacity(0.25)),
            ),
            child: Row(
              children: [
                const SizedBox(width: 12),
                // Play/Pause button
                IconButton(
                  icon: Icon(
                    isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: 24,
                  ),
                  onPressed: () {
                    if (isPlaying) {
                      app_main.audioService.pause();
                    } else if (info.currentMaterialId == 0) {
                      onPlayCurrent();
                    } else {
                      app_main.audioService.play();
                    }
                  },
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 8),
                // Title + subtitle
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        current.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isPlaying ? '正在播放' : '已暂停',
                        style: TextStyle(
                          fontSize: 11,
                          color: isPlaying
                              ? cs.primary
                              : Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ),
                // Mode toggle
                GestureDetector(
                  onTap: onTapMode,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          info.playModeLabel,
                          style: const TextStyle(
                              fontSize: 10, color: Colors.white38),
                        ),
                        const SizedBox(width: 2),
                        const Icon(Icons.chevron_right,
                            size: 18, color: Colors.white38),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
