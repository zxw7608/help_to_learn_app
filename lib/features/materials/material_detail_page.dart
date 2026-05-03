import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api/materials_api.dart';
import '../../core/api/users_api.dart';
import '../../core/api/api_client.dart';
import '../../core/models/material.dart';
import '../../core/models/segment.dart';
import '../../core/services/anki_service.dart';
import '../../core/services/cache_service.dart';
import '../../core/services/playlist_manager.dart';
import 'dart:async';
import '../../core/logging/app_logger.dart';
import '../../main.dart' as app_main;

class MaterialDetailPage extends ConsumerStatefulWidget {
  final int materialId;
  final bool autoPlay;
  const MaterialDetailPage({super.key, required this.materialId, this.autoPlay = false});

  @override
  ConsumerState<MaterialDetailPage> createState() =>
      _MaterialDetailPageState();
}

class _MaterialDetailPageState extends ConsumerState<MaterialDetailPage> {
  MaterialModel? _material;
  List<SegmentModel> _segments = [];
  bool _loading = true;
  String? _error;
  bool _isPlayingAll = false;
  bool _isPlayingSelected = false;
  int? _playingIndex;
  bool _pushingAll = false;
  final _scrollController = ScrollController();
  final Map<int, GlobalKey> _itemKeys = {};
  bool _userDragging = false;
  int? _pendingScrollIndex;
  bool _wasPlaying = false;

  VoidCallback? _playbackListener;
  PlaylistManager? _playlistManager;

  @override
  void initState() {
    super.initState();
    _load();
    AppLogger.info('MaterialDetailPage: id=${widget.materialId}',
        tag: 'MaterialDetail');

    _playlistManager = ref.read(playlistManagerProvider.notifier);

    final service = app_main.audioService;
    _playbackListener = () {
      if (!mounted) return;
      bool needsRebuild = false;
      final segId = service.currentSegmentId;
      if (segId != null) {
        final index = _segments.indexWhere((s) => s.id.toString() == segId);
        if (index != -1 && index != _playingIndex) {
          _playingIndex = index;
          needsRebuild = true;
          _scrollToIndex(index);
        } else if (index == -1 && _playingIndex != null) {
          // Current segment belongs to a different material — reset
          _playingIndex = null;
          _isPlayingAll = false;
          _isPlayingSelected = false;
          _wasPlaying = false;
          needsRebuild = true;
        }
      } else if (_playingIndex != null || _wasPlaying) {
        // Playback stopped entirely
        _playingIndex = null;
        _isPlayingAll = false;
        _isPlayingSelected = false;
        _wasPlaying = false;
        needsRebuild = true;
      }
      final nowPlaying = service.playbackInfo.value.playing;
      if (nowPlaying != _wasPlaying) {
        _wasPlaying = nowPlaying;
        needsRebuild = true;
      }
      if (needsRebuild) {
        try { setState(() {}); } catch (_) {}
      }
    };
    service.playbackInfo.addListener(_playbackListener!);

    // Wire notification "Push to Anki" button
    service.onRequestAnkiPush = () => _pushCurrentToAnki();

    // Prompt when playlist auto-advances to another material
    _playlistManager!.onMaterialSwitched = (newId) {
      if (mounted && newId != widget.materialId) {
        _showNavigatePrompt(newId);
      }
    };
  }

  @override
  void dispose() {
    // Unregister notification Anki callback
    app_main.audioService.onRequestAnkiPush = null;
    _playlistManager?.onMaterialSwitched = null;
    if (_playbackListener != null) {
      app_main.audioService.playbackInfo.removeListener(_playbackListener!);
    }
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final mat = await materialsApi.get(widget.materialId);
      final segsRaw = await materialsApi.getSegmentsRaw(widget.materialId);
      final segs = segsRaw.map(SegmentModel.fromJson).toList();
      setState(() {
        _material = mat;
        _segments = segs;
        _loading = false;
      });
      // Pre-cache all audio in background
      CacheService.instance.preCacheMaterial(segs.map((s) => s.id).toList());

      // Sync with current playback state if this material is already playing
      if (segs.isNotEmpty) {
        final service = app_main.audioService;
        final info = service.playbackInfo.value;
        if (info.currentMaterialId == widget.materialId) {
          final segId = service.currentSegmentId;
          final idx = segId != null
              ? segs.indexWhere((s) => s.id.toString() == segId)
              : -1;
          setState(() {
            if (idx != -1) {
              _playingIndex = idx;
              _isPlayingSelected = true;
              _isPlayingAll = false;
            }
            _wasPlaying = info.playing;
          });
          if (idx != -1) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _scrollToIndex(idx);
            });
          }
        }
      }

      // Auto-play if navigated from notification material change
      if (widget.autoPlay && segs.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _startSequential(0);
        });
      }
    } catch (e, st) {
      AppLogger.error('Failed to load material detail',
          tag: 'MaterialDetail', error: e, stackTrace: st);
      setState(() {
        _error = '加载失败：$e';
        _loading = false;
      });
    }
  }

  void _scrollToIndex(int index) {
    if (!_scrollController.hasClients) return;
    if (_userDragging) {
      _pendingScrollIndex = index;
      return;
    }
    final key = _itemKeys[index];
    if (key?.currentContext != null) {
      // Item is already built — accurate positioning.
      Scrollable.ensureVisible(
        key!.currentContext!,
        alignment: 0.1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      // Item is off-screen and not yet built. Scroll to an estimated
      // offset, then fine-tune once the item appears in the tree.
      final estimatedOffset = index * 100.0;
      final maxScroll = _scrollController.position.maxScrollExtent;
      _scrollController.animateTo(
        estimatedOffset.clamp(0.0, maxScroll),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      ).then((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final key2 = _itemKeys[index];
        if (key2?.currentContext != null) {
          Scrollable.ensureVisible(
            key2!.currentContext!,
            alignment: 0.1,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeInOut,
          );
        }
      });
    }
  }

  void _showNavigatePrompt(int newMaterialId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('已切换素材'),
        content: const Text('播放已切换到下一个素材，是否跳转到新素材详情页？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              GoRouter.of(context).push('/material/$newMaterialId');
            },
            child: const Text('跳转'),
          ),
        ],
      ),
    );
  }

  // ─── Playback ─────────────────────────────────────────────────────────────

  Future<void> _startSequential(int fromIndex, {bool isSelectedMode = false}) async {
    final service = app_main.audioService;

    // Ensure material is in the playlist
    final playlist = ref.read(playlistManagerProvider);
    final alreadyInPlaylist = playlist.entries.any((e) => e.materialId == widget.materialId);
    if (!alreadyInPlaylist) {
      await ref.read(playlistManagerProvider.notifier).addMaterials([widget.materialId]);
    }

    setState(() {
      _isPlayingAll = !isSelectedMode;
      _isPlayingSelected = isSelectedMode;
      _playingIndex = fromIndex;
    });
    final ok = await service.loadMaterial(
      segments: _segments,
      materialTitle: _material?.title ?? '未知素材',
      materialId: widget.materialId,
      startIndex: fromIndex,
      sequential: true,
    );
    if (ok) await service.play();
  }

  Future<void> _playOrPauseSingle(int index) async {
    final service = app_main.audioService;
    if (_playingIndex == index) {
      if (service.playbackInfo.value.playing) {
        await service.pause();
      } else {
        await service.play();
      }
      return;
    }
    // Ensure material is in the playlist
    final playlist = ref.read(playlistManagerProvider);
    final alreadyInPlaylist = playlist.entries.any((e) => e.materialId == widget.materialId);
    if (!alreadyInPlaylist) {
      await ref.read(playlistManagerProvider.notifier).addMaterials([widget.materialId]);
    }
    setState(() {
      _isPlayingAll = false;
      _isPlayingSelected = false;
      _playingIndex = index;
    });
    final ok = await service.loadMaterial(
      segments: _segments,
      materialTitle: _material?.title ?? '未知素材',
      materialId: widget.materialId,
      startIndex: index,
      sequential: false,
    );
    if (ok) await service.play();
  }

  Future<void> _pauseOrStop() async {
    await app_main.audioService.pause();
  }

  // ─── Anki push ────────────────────────────────────────────────────────────

  Future<void> _pushCurrentToAnki() async {
    final segment = app_main.audioService.currentSegment;
    if (segment == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⚠️ 无当前片段'), duration: Duration(seconds: 2)),
        );
      }
      return;
    }
    await _pushSingleToAnki(segment);
  }

  Future<void> _pushSingleToAnki(SegmentModel segment) async {
    final user = await usersApi.getMe();
    try {
      await AnkiService.instance.pushSegment(
        segment,
        deckName: user.ankiDeckName,
        modelName: user.ankiModelName,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('✅ 已加入Anki'),
              duration: Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('❌ Anki推送失败: $e'),
              backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
  }

  Future<void> _pushAllToAnki() async {
    setState(() => _pushingAll = true);
    final user = await usersApi.getMe();
    int done = 0;
    try {
      final results = await AnkiService.instance.pushSegments(
        _segments,
        deckName: user.ankiDeckName,
        modelName: user.ankiModelName,
        onProgress: (d, total) {
          done = d;
          if (mounted) setState(() {});
        },
      );
      final ok = results.where((r) => r.success).length;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('✅ 批量导入完成: $ok/${_segments.length} 成功')),
        );
      }
    } catch (e, st) {
      AppLogger.error('Bulk Anki push failed',
          tag: 'MaterialDetail', error: e, stackTrace: st);
    } finally {
      setState(() => _pushingAll = false);
    }
  }

  void _shareMaterial() {
    if (_material == null) return;
    final url = '${ApiClient.baseUrl}/share/${widget.materialId}';
    Share.share(url, subject: _material!.title);
  }

  void _shareSegment(SegmentModel segment, int index) {
    final url = '${ApiClient.baseUrl}/share/${widget.materialId}#seg-${segment.id}';
    Share.share(url, subject: segment.text);
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('加载中...')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null || _material == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('错误')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error ?? '未知错误',
                  style: const TextStyle(color: Colors.redAccent)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试')),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onLongPress: () {
            showModalBottomSheet(
              context: context,
              backgroundColor: const Color(0xFF1E1E2E),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              ),
              builder: (ctx) => SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.share, color: Colors.white),
                      title: const Text('分享整个素材', style: TextStyle(color: Colors.white)),
                      onTap: () {
                        Navigator.pop(ctx);
                        _shareMaterial();
                      },
                    ),
                  ],
                ),
              ),
            );
          },
          child: Text(_material!.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: '分享素材',
            onPressed: _shareMaterial,
          ),
          // Bulk Anki push
          if (_pushingAll)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            IconButton(
              icon: const Icon(Icons.style_outlined),
              tooltip: '全部导入Anki',
              onPressed: _segments.isEmpty ? null : _pushAllToAnki,
            ),
        ],
      ),
      body: Column(
        children: [
          // Material info banner
          _MaterialInfoBanner(material: _material!),

          // Sequential play controls
          _PlayControls(
            segmentCount: _segments.length,
            isPlayingAll: _isPlayingAll && app_main.audioService.playbackInfo.value.playing,
            isPlayingSelected: _isPlayingSelected && app_main.audioService.playbackInfo.value.playing,
            onPlayAll: () => _startSequential(0, isSelectedMode: false),
            onPlaySelected: _playingIndex != null ? () => _startSequential(_playingIndex!, isSelectedMode: true) : null,
            onPause: _pauseOrStop,
          ),

          // Segment list
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is ScrollStartNotification &&
                    notification.dragDetails != null) {
                  _userDragging = true;
                } else if (notification is ScrollEndNotification) {
                  _userDragging = false;
                  if (_pendingScrollIndex != null) {
                    final idx = _pendingScrollIndex!;
                    _pendingScrollIndex = null;
                    _scrollToIndex(idx);
                  }
                }
                return false;
              },
              child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
              itemCount: _segments.length,
              itemBuilder: (ctx, i) {
                final seg = _segments[i];
                _itemKeys.putIfAbsent(i, () => GlobalKey());
                final segIdStr = seg.id.toString();
                final isCurrentSegment = app_main.audioService.currentSegmentId == segIdStr;
                return Container(
                  key: _itemKeys[i],
                  child: _SegmentCard(
                    segment: seg,
                    index: i,
                    isPlaying: _playingIndex == i,
                    isAudioPlaying: isCurrentSegment && app_main.audioService.playbackInfo.value.playing,
                    onPlayOrPause: () => _playOrPauseSingle(i),
                    onSelect: () => setState(() => _playingIndex = i),
                    onPushAnki: () => _pushSingleToAnki(seg),
                    onLongPressShare: () => _shareSegment(seg, i),
                  ),
                );
              },
            ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Sub-widgets ─────────────────────────────────────────────────────────────

class _MaterialInfoBanner extends StatelessWidget {
  final MaterialModel material;
  const _MaterialInfoBanner({required this.material});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Theme.of(context).colorScheme.surface,
      child: Row(
        children: [
          Icon(material.statusEmoji == '✅'
              ? Icons.check_circle
              : Icons.schedule, size: 18, color: Colors.white54),
          const SizedBox(width: 8),
          Text(material.status.name,
              style: const TextStyle(color: Colors.white54, fontSize: 13)),
          const Spacer(),
          Text(material.language.toUpperCase(),
              style: const TextStyle(color: Colors.white54, fontSize: 13)),
          if (material.durationFormatted.isNotEmpty) ...[
            const SizedBox(width: 12),
            Text(material.durationFormatted,
                style: const TextStyle(color: Colors.white54, fontSize: 13)),
          ],
        ],
      ),
    );
  }
}

class _PlayControls extends StatelessWidget {
  final int segmentCount;
  final bool isPlayingAll;
  final bool isPlayingSelected;
  final VoidCallback onPlayAll;
  final VoidCallback onPause;
  final VoidCallback? onPlaySelected;

  const _PlayControls({
    required this.segmentCount,
    required this.isPlayingAll,
    required this.isPlayingSelected,
    required this.onPlayAll,
    required this.onPause,
    this.onPlaySelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: const Border(bottom: BorderSide(color: Color(0xFF2A2A3E))),
      ),
      child: Row(
        children: [
          Text('$segmentCount片段',
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const Spacer(),
          TextButton.icon(
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            ),
            onPressed: isPlayingAll ? onPause : onPlayAll,
            icon: Icon(isPlayingAll ? Icons.pause_circle : Icons.play_circle,
                size: 16),
            label: Text(isPlayingAll ? '暂停' : '顺序全部', style: const TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 4),
          TextButton.icon(
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            ),
            onPressed: isPlayingSelected ? onPause : onPlaySelected,
            icon: Icon(isPlayingSelected ? Icons.pause_circle : Icons.playlist_play, size: 16),
            label: Text(isPlayingSelected ? '暂停' : '选中播放', style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _SegmentCard extends StatelessWidget {
  final SegmentModel segment;
  final int index;
  final bool isPlaying;
  final bool isAudioPlaying;
  final VoidCallback onPlayOrPause;
  final VoidCallback onSelect;
  final VoidCallback onPushAnki;
  final VoidCallback onLongPressShare;

  const _SegmentCard({
    required this.segment,
    required this.index,
    required this.isPlaying,
    required this.isAudioPlaying,
    required this.onPlayOrPause,
    required this.onSelect,
    required this.onPushAnki,
    required this.onLongPressShare,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isPlaying ? cs.primary.withOpacity(0.6) : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: InkWell(
        onTap: onSelect,
        onLongPress: () {
          showModalBottomSheet(
            context: context,
            backgroundColor: const Color(0xFF1E1E2E),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
            ),
            builder: (ctx) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.share, color: Colors.white),
                    title: const Text('分享该片段', style: TextStyle(color: Colors.white)),
                    onTap: () {
                      Navigator.pop(ctx);
                      onLongPressShare();
                    },
                  ),
                ],
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Index badge
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: isPlaying
                          ? cs.primary.withOpacity(0.25)
                          : Colors.white10,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isPlaying ? cs.primary : Colors.white54),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SelectableText(
                      segment.text,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isPlaying ? Colors.white : const Color(0xDEFFFFFF),
                      ),
                    ),
                  ),
                ],
              ),
              if (segment.translation != null && segment.translation!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(left: 34),
                  child: SelectableText(
                    segment.translation!,
                    style: const TextStyle(
                        fontSize: 12, color: Colors.white54),
                  ),
                ),
              ],
              // Actions row
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                alignment: WrapAlignment.end,
                children: [
                  // Single play button
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: isPlaying ? cs.primary : Colors.white54,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                    ),
                    icon: Icon(
                      isAudioPlaying ? Icons.pause : Icons.play_arrow,
                      size: 16,
                    ),
                    label: Text(isAudioPlaying ? '暂停' : '单句播放', style: const TextStyle(fontSize: 12)),
                    onPressed: onPlayOrPause,
                  ),
                  // Push to Anki
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white54,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                    ),
                    icon: const Icon(Icons.style, size: 16),
                    label: const Text('加入Anki', style: TextStyle(fontSize: 12)),
                    onPressed: onPushAnki,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
