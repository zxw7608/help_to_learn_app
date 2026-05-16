import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api/materials_api.dart';
import '../../core/api/users_api.dart';
import '../../core/api/api_client.dart';
import '../../core/api/analysis_api.dart';
import '../../core/models/material.dart';
import '../../core/models/segment.dart';
import '../../core/models/analysis_record.dart';
import '../../core/models/user.dart';
import '../../core/services/anki_service.dart';
import '../../core/services/cache_service.dart';
import '../../core/services/playlist_manager.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
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

  // AI Analysis state
  final Map<int, String> _analysisPreviews = {};
  bool _analyzing = false;
  String? _analysisPhrase;
  String? _analysisResult;
  List<AnalysisRecord> _analysisRecords = [];
  bool _loadingRecords = false;
  int _recordsSegIndex = 0;
  UserModel? _userConfig;

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

      // Load user config (for AI settings)
      try {
        _userConfig = await usersApi.getMe();
      } catch (_) {}

      // Load analysis previews
      _loadAnalysisPreviews();

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
              GoRouter.of(context).push('/materials/$newMaterialId');
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
        analysisText: _analysisPreviews[segment.id],
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
        analysisMap: _analysisPreviews,
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

  // ─── AI Analysis ──────────────────────────────────────────────────────────

  Future<void> _loadAnalysisPreviews() async {
    if (_segments.isEmpty) return;
    try {
      final records = await analysisApi.list(size: 200);
      final previews = <int, String>{};
      for (final r in records) {
        previews.putIfAbsent(r.segmentId, () => r.analysis);
      }
      if (mounted) setState(() {
        _analysisPreviews.clear();
        _analysisPreviews.addAll(previews);
      });
    } catch (_) {}
  }

  Future<void> _doAnalyze(int segId, String phrase) async {
    if (_userConfig?.aiBaseUrl == null || _userConfig?.aiApiKey == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先在设置中配置 AI Base URL 和 API Key')),
        );
      }
      return;
    }

    setState(() {
      _analyzing = true;
      _analysisPhrase = phrase;
      _analysisResult = null;
    });

    _showAnalysisResultSheet();

    try {
      final idx = _segments.indexWhere((s) => s.id == segId);
      final contextSegments = <Map<String, dynamic>>[];
      if (idx != -1) {
        final start = (idx - 1).clamp(0, _segments.length);
        final end = (idx + 1).clamp(0, _segments.length - 1);
        for (var i = start; i <= end; i++) {
          contextSegments.add({
            'index': _segments[i].index,
            'text': _segments[i].text,
          });
        }
      }
      final contextStr =
          contextSegments.map((c) => '[#${c['index']}] ${c['text']}').join('\n');

      final seg = _segments.firstWhere((s) => s.id == segId);
      final segText = seg.text;
      final phraseIdx = segText.indexOf(phrase);
      String immediateContext = phrase;
      if (phraseIdx != -1) {
        final before = segText.substring(0, phraseIdx).trim();
        final after = segText.substring(phraseIdx + phrase.length).trim();
        final beforeParts = before.split(RegExp(r'\s+'));
        final afterParts = after.split(RegExp(r'\s+'));
        final beforeWords = beforeParts
            .sublist((beforeParts.length - 5).clamp(0, beforeParts.length))
            .join(' ');
        final afterWords = afterParts.take(5).join(' ');
        immediateContext = '$beforeWords **$phrase** $afterWords'.trim();
      }

      const defaultPrompt =
          // ignore: lines_longer_than_80_chars
          "You are an English language tutor. Analyze the phrase \"\${phrase}\" from this sentence: \"\${immediateContext}\"\n\nFull transcript context:\n\${contextStr}\n\nPlease provide a concise analysis in Chinese:\n\n1. 风格要求：\n\n极简： 能用 5 个字说明白，绝不用 10 个字。\n\n大白话： 像跟 5 岁小朋友说话一样，直白、简单。\n\n拒绝脑补： 不要分析心路历程，只说最直观的意思。\n\n2. 结构要求：\n\n短语整体含义：一句话说明在文中的意思。\n\n逐词解析：\n\n介词/副词/表语：给出在文中的意境，这里要用英文解释\n\n高级/核心词：用最简单的同义词替换，这里要用英文解释\n\n例句：1-2 个极简的常用句子。\n\n3. 负面约束（禁止出现）：\n\n禁止说\"前者...后者...\"。\n\n禁止说\"隐喻\"、\"由下而上\"、\"发展轨迹\"、\"社会性成熟\"等虚词。\n\n禁止进行深度语义对比。\n\nKeep it concise. Use plain text, no markdown other than **bold** for headers.";

      final promptTemplate = (_userConfig?.aiPrompt?.isNotEmpty ?? false)
          ? _userConfig!.aiPrompt!
          : defaultPrompt;
      final prompt = promptTemplate
          .replaceAll(r'${phrase}', phrase)
          .replaceAll(r'${immediateContext}', immediateContext)
          .replaceAll(r'${contextStr}', contextStr);

      final baseUrl = _userConfig!.aiBaseUrl!.replaceAll(RegExp(r'/+$'), '');
      final response = await Dio().post(
        '$baseUrl/chat/completions',
        data: {
          'model': _userConfig!.aiModel ?? 'gpt-3.5-turbo',
          'messages': [
            {'role': 'user', 'content': prompt}
          ],
          'temperature': 0.7,
          'max_tokens': 800,
        },
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${_userConfig!.aiApiKey}',
          },
          receiveTimeout: const Duration(seconds: 60),
        ),
      );

      final data = response.data as Map<String, dynamic>;
      final analysis = data['choices']?[0]?['message']?['content'] as String? ??
          'No analysis returned';

      await analysisApi.save(segId,
          selectedPhrase: phrase, analysis: analysis);

      setState(() {
        _analysisResult = analysis;
        _analysisPreviews[segId] = analysis;
        _analyzing = false;
      });

      // Dismiss the loading sheet and show the result
      if (mounted) {
        Navigator.pop(context);
        _showAnalysisResultSheet();
      }
    } catch (e) {
      setState(() => _analyzing = false);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('解析失败: $e'),
              backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
  }

  void _showAnalysisResultSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E2E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          // final maxContentHeight = MediaQuery.of(ctx).size.height * 0.6;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('AI 解析结果',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  if (_analysisPhrase != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('选中短语: $_analysisPhrase',
                          style: const TextStyle(color: Color(0xFF6f42c1))),
                    ),
                  const Divider(color: Color(0xFF2A2A3E)),
                  if (_analyzing)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(40),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (_analysisResult != null)
                    Flexible (
                      child: SingleChildScrollView(
                        scrollDirection: Axis.vertical, // 明确指定方向
                        physics: AlwaysScrollableScrollPhysics(), // 强制可滚动
                        child: _buildAnalysisWidget(_analysisResult!),
                      ),
                    )
                  else
                    const Text('暂无结果',
                        style: TextStyle(color: Colors.white54)),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('关闭'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAnalysisWidget(String text) {
    return SelectableText(
      text,
      style: const TextStyle(
        color: Color(0xFFCCCCCC),
        fontSize: 14,
        height: 1.6,
      ),
    );
  }

  Future<void> _showAnalysisRecords(SegmentModel seg) async {
    setState(() {
      _loadingRecords = true;
      _recordsSegIndex = seg.index;
      _analysisRecords = [];
    });

    try {
      final records = await analysisApi.forSegment(seg.id);
      if (mounted) setState(() => _analysisRecords = records);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('加载解析记录失败'),
              backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingRecords = false);
    }

    if (mounted) {
      showModalBottomSheet(
        context: context,
        backgroundColor: const Color(0xFF1E1E2E),
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        builder: (ctx) {
          final maxHeight = MediaQuery
              .of(ctx)
              .size
              .height * 0.65;
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('AI 解析记录 - 片段 #$_recordsSegIndex',
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                    const Divider(color: Color(0xFF2A2A3E)),
                    if (_loadingRecords)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(40),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else
                      if (_analysisRecords.isEmpty)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(40),
                            child: Text('暂无解析记录',
                                style: TextStyle(color: Colors.white54)),
                          ),
                        )
                      else
                        Flexible(
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: _analysisRecords.length,
                            itemBuilder: (ctx, i) {
                              final rec = _analysisRecords[i];
                              return Card(
                                color: const Color(0xFF2A2A3E),
                                margin: const EdgeInsets.only(bottom: 8),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment
                                        .start,
                                    children: [
                                      Text('选中短语: ${rec.selectedPhrase}',
                                          style: const TextStyle(
                                              color: Color(0xFF6f42c1),
                                              fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 8),
                                      _buildAnalysisWidget(rec.analysis),
                                      const SizedBox(height: 8),
                                      Text(
                                        rec.createdAt.toLocal().toString(),
                                        style: const TextStyle(
                                            color: Colors.white38,
                                            fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('关闭'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }
  }

  void _showAnalyzeDialog(SegmentModel seg, {String prefill = ''}) {
    final phraseCtrl = TextEditingController(text: prefill);
    // Try to pre-fill from clipboard if no explicit prefill
    if (prefill.isEmpty) {
      Clipboard.getData(Clipboard.kTextPlain).then((data) {
        final clip = data?.text?.trim() ?? '';
        if (clip.isNotEmpty && phraseCtrl.text.isEmpty) {
          phraseCtrl.text = clip;
        }
      });
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('AI 解析', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              constraints: const BoxConstraints(maxHeight: 120),
              child: SingleChildScrollView(
                child: Text(seg.text,
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phraseCtrl,
              decoration: const InputDecoration(
                labelText: '输入要解析的短语',
                hintText: '从上方原文中选择或输入短语...',
                labelStyle: TextStyle(color: Colors.white54),
                hintStyle: TextStyle(color: Colors.white30),
              ),
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              final phrase = phraseCtrl.text.trim();
              if (phrase.isNotEmpty) {
                Navigator.pop(ctx);
                _doAnalyze(seg.id, phrase);
              }
            },
            child: const Text('解析'),
          ),
        ],
      ),
    );
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

  // ─── Actions ──────────────────────────────────────────────────────────────

  Future<void> _reExecute() async {
    try {
      await materialsApi.reExecute(widget.materialId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已提交重新执行'), duration: Duration(seconds: 2)),
        );
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('重新执行失败: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _cleanupStorage() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('清理存储', style: TextStyle(color: Colors.white)),
        content: const Text('确定清理该素材的音频文件吗？素材记录会保留。',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('清理', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await materialsApi.deleteMaterialStorage(widget.materialId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('存储已清理'), duration: Duration(seconds: 2)),
        );
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('清理失败: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _deleteMaterial() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('删除素材', style: TextStyle(color: Colors.white)),
        content: const Text('确定删除该素材吗？此操作不可恢复。',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await materialsApi.deleteMaterial(widget.materialId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('素材已删除'), duration: Duration(seconds: 2)),
        );
        GoRouter.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
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
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: '分享素材',
            onPressed: _shareMaterial,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            color: const Color(0xFF1E1E2E),
            onSelected: (action) {
              switch (action) {
                case 're-execute':
                  _reExecute();
                  break;
                case 'cleanup':
                  _cleanupStorage();
                  break;
                case 'delete':
                  _deleteMaterial();
                  break;
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 're-execute',
                child: ListTile(
                  leading: Icon(Icons.refresh, color: Colors.white),
                  title: Text('重新执行', style: TextStyle(color: Colors.white)),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'cleanup',
                child: ListTile(
                  leading: Icon(Icons.cleaning_services, color: Colors.white),
                  title: Text('清理存储', style: TextStyle(color: Colors.white)),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_outline, color: Colors.redAccent),
                  title: Text('删除素材', style: TextStyle(color: Colors.redAccent)),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
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
                    analysisPreview: _analysisPreviews[seg.id],
                    onAnalyze: (phrase) => _doAnalyze(seg.id, phrase),
                    onShowAnalyzeDialog: () => _showAnalyzeDialog(seg),
                    onShowRecords: () => _showAnalysisRecords(seg),
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
  final String? analysisPreview;
  final VoidCallback? onShowRecords;
  final void Function(String phrase)? onAnalyze;
  final VoidCallback? onShowAnalyzeDialog;

  const _SegmentCard({
    required this.segment,
    required this.index,
    required this.isPlaying,
    required this.isAudioPlaying,
    required this.onPlayOrPause,
    required this.onSelect,
    required this.onPushAnki,
    required this.onLongPressShare,
    this.analysisPreview,
    this.onShowRecords,
    this.onAnalyze,
    this.onShowAnalyzeDialog,
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
                    leading: const Icon(Icons.psychology,
                        color: Color(0xFF6f42c1)),
                    title: const Text('AI 解析',
                        style: TextStyle(color: Colors.white)),
                    subtitle: Text(segment.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 12)),
                    onTap: () {
                      Navigator.pop(ctx);
                      onShowAnalyzeDialog?.call();
                    },
                  ),
                  ListTile(
                    leading:
                        const Icon(Icons.history, color: Colors.white54),
                    title: const Text('AI解析记录',
                        style: TextStyle(color: Colors.white)),
                    onTap: () {
                      Navigator.pop(ctx);
                      onShowRecords?.call();
                    },
                  ),
                  ListTile(
                    leading:
                        const Icon(Icons.copy, color: Colors.white),
                    title: const Text('复制原文',
                        style: TextStyle(color: Colors.white)),
                    onTap: () {
                      Clipboard.setData(
                          ClipboardData(text: segment.text));
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已复制到剪贴板')),
                      );
                    },
                  ),
                  ListTile(
                    leading:
                        const Icon(Icons.share, color: Colors.white),
                    title: const Text('分享该片段',
                        style: TextStyle(color: Colors.white)),
                    onTap: () {
                      Navigator.pop(ctx);
                      onLongPressShare();
                    },
                  ),
                  ListTile(
                    leading:
                        const Icon(Icons.style, color: Colors.white54),
                    title: const Text('加入Anki',
                        style: TextStyle(color: Colors.white)),
                    onTap: () {
                      Navigator.pop(ctx);
                      onPushAnki();
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
                    child: SelectionArea(
                      contextMenuBuilder: (ctx, state) {
                              return AdaptiveTextSelectionToolbar.buttonItems(
                                anchors: state.contextMenuAnchors,
                                buttonItems: [
                                  ContextMenuButtonItem(
                                    label: '解析',
                                    onPressed: () {
                                      state.copySelection(
                                          SelectionChangedCause.toolbar);
                                      Clipboard.getData(Clipboard.kTextPlain)
                                          .then((data) {
                                        final phrase = data?.text?.trim() ?? '';
                                        ContextMenuController.removeAny();
                                        if (phrase.isNotEmpty) {
                                          onAnalyze?.call(phrase);
                                        }
                                      });
                                    },
                                  ),
                                  ContextMenuButtonItem(
                                    label: '复制',
                                    onPressed: () {
                                      state.copySelection(
                                          SelectionChangedCause.toolbar);
                                      ContextMenuController.removeAny();
                                    },
                                  ),
                                  ContextMenuButtonItem(
                                    label: '分享',
                                    onPressed: () {
                                      state.copySelection(
                                          SelectionChangedCause.toolbar);
                                      Clipboard.getData(Clipboard.kTextPlain)
                                          .then((data) {
                                        final text = data?.text?.trim() ?? '';
                                        ContextMenuController.removeAny();
                                        if (text.isNotEmpty) {
                                          Share.share(text);
                                        }
                                      });
                                    },
                                  ),
                                ],
                              );
                            },
                      child: Text(
                        segment.text,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color:
                              isPlaying ? Colors.white : const Color(0xDEFFFFFF),
                        ),
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
                  // AI analysis records
                  if (onShowRecords != null)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF6f42c1),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                      ),
                      icon: const Icon(Icons.psychology, size: 16),
                      label: const Text('AI解析记录',
                          style: TextStyle(fontSize: 12)),
                      onPressed: onShowRecords,
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
