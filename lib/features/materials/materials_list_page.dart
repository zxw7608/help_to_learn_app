import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../core/api/materials_api.dart';
import '../../core/models/material.dart';
import '../../core/logging/app_logger.dart';
import '../../core/services/playlist_manager.dart';

class MaterialsListPage extends ConsumerStatefulWidget {
  final bool temporary;
  const MaterialsListPage({super.key, this.temporary = false});

  @override
  ConsumerState<MaterialsListPage> createState() => _MaterialsListPageState();
}

class _MaterialsListPageState extends ConsumerState<MaterialsListPage>
    with WidgetsBindingObserver {
  final _scrollController = ScrollController();
  List<MaterialModel> _materials = [];
  bool _loading = true;
  bool _loadingMore = false;
  int _page = 1;
  int _total = 0;
  String? _error;

  bool _selectionMode = false;
  final _selectedIds = <int>{};

  String? _lastClipboardText;

  bool get _isTemporary => widget.temporary;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    _loadMaterials();
    AppLogger.info('MaterialsListPage opened (temporary=$_isTemporary)',
        tag: 'MaterialsList');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    super.dispose();
  }

  // ─── Clipboard monitoring ─────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkClipboard();
    }
  }

  Future<void> _checkClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim();
      if (text == null || text.isEmpty) return;
      if (text == _lastClipboardText) return;

      if (_isUrl(text) || text.length > 30) {
        _lastClipboardText = text;
        if (mounted) _showClipboardDialog(text);
      }
    } catch (e) {
      AppLogger.verbose('Clipboard check error', tag: 'MaterialsList', data: e);
    }
  }

  bool _isUrl(String text) {
    return text.startsWith('http://') || text.startsWith('https://');
  }

  void _showClipboardDialog(String text) {
    final preview = text.length > 80 ? '${text.substring(0, 80)}...' : text;
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.content_paste, size: 20),
                const SizedBox(width: 8),
                const Text('检测到剪切板内容',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(preview,
                  style:
                      const TextStyle(fontSize: 13, color: Colors.white70)),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('忽略'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      context.pushNamed('add-material',
                          queryParameters: {'url': text});
                    },
                    child: const Text('添加素材'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ─── Data loading ─────────────────────────────────────────────────────────

  Future<void> _loadMaterials({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _page = 1;
        _materials = [];
        _loading = true;
        _error = null;
      });
    }

    try {
      final result = await materialsApi.list(
        page: _page,
        size: 20,
        materialType: _isTemporary ? 'temporary' : 'main',
      );
      setState(() {
        _materials =
            refresh ? result.items : [..._materials, ...result.items];
        _total = result.total;
        _loading = false;
        _loadingMore = false;
      });
      AppLogger.debug('Loaded ${result.items.length} materials (page $_page)',
          tag: 'MaterialsList');
    } catch (e, st) {
      AppLogger.error('Failed to load materials',
          tag: 'MaterialsList', error: e, stackTrace: st);
      setState(() {
        _error = '加载失败，下拉重试';
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  void _loadMore() {
    if (_loadingMore || _materials.length >= _total) return;
    setState(() {
      _loadingMore = true;
      _page++;
    });
    _loadMaterials();
  }

  // ─── Selection ────────────────────────────────────────────────────────────

  void _enterSelectionMode(int materialId) {
    setState(() {
      _selectionMode = true;
      _selectedIds.add(materialId);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelection(int materialId) {
    setState(() {
      if (_selectedIds.contains(materialId)) {
        _selectedIds.remove(materialId);
        if (_selectedIds.isEmpty) {
          _selectionMode = false;
        }
      } else {
        _selectedIds.add(materialId);
      }
    });
  }

  Future<void> _addToPlaylist({bool playNow = false}) async {
    if (_selectedIds.isEmpty) return;
    final ids = _selectedIds.toList();
    _exitSelectionMode();
    await ref
        .read(playlistManagerProvider.notifier)
        .addMaterials(ids, playNow: playNow);
    if (mounted) {
      final msg = playNow ? '已添加到播放列表并开始播放' : '已添加到播放列表';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          duration: const Duration(seconds: 2),
          action: SnackBarAction(
            label: '查看',
            onPressed: () => context.go('/playlist'),
          ),
        ),
      );
      if (playNow) {
        context.pushNamed('player');
      }
    }
  }

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('批量删除', style: TextStyle(color: Colors.white)),
        content: Text('确定删除选中的 ${_selectedIds.length} 个素材吗？',
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirmed != true) return;

    final ids = _selectedIds.toList();
    _exitSelectionMode();
    for (final id in ids) {
      try { await materialsApi.deleteMaterial(id); } catch (_) {}
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('批量删除完成'), duration: Duration(seconds: 2)),
      );
      _loadMaterials(refresh: true);
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _selectionMode
            ? Text('已选 ${_selectedIds.length} 个')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_isTemporary ? '临时素材' : '素材'),
                  if (_total > 0)
                    Text('共 $_total 个',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.white54)),
                ],
              ),
        leading: _selectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _exitSelectionMode,
              )
            : null,
        actions: [
          if (_selectionMode && _selectedIds.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '批量删除',
              onPressed: _deleteSelected,
            ),
          if (_selectionMode)
            IconButton(
              icon: const Icon(Icons.select_all),
              tooltip: '全选',
              onPressed: () {
                setState(() {
                  if (_selectedIds.length == _materials.length) {
                    _selectedIds.clear();
                    _selectionMode = false;
                  } else {
                    _selectedIds.addAll(_materials.map((m) => m.id));
                  }
                });
              },
            )
          else
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              tooltip: '添加素材',
              onPressed: () => context.pushNamed('add-material', queryParameters: {
                if (_isTemporary) 'temporary': 'true',
              }),
            ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: _selectionMode && _selectedIds.isNotEmpty
          ? _buildSelectionBar()
          : null,
    );
  }

  Widget _buildSelectionBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          color: Color(0xFF1E1E2E),
          border:
              Border(top: BorderSide(color: Color(0xFF2A2A3E), width: 1)),
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _addToPlaylist(playNow: false),
                icon: const Icon(Icons.playlist_add, size: 18),
                label: const Text('添加到播放列表'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _addToPlaylist(playNow: true),
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('立即播放'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return _buildShimmer();
    if (_error != null && _materials.isEmpty) return _buildError();

    return RefreshIndicator(
      onRefresh: () => _loadMaterials(refresh: true),
      child: _materials.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.7,
                  child: _buildEmpty(),
                ),
              ],
            )
          : ListView.builder(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              itemCount: _materials.length + (_loadingMore ? 1 : 0),
              itemBuilder: (ctx, i) {
                if (i == _materials.length) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final mat = _materials[i];
                final isSelected = _selectedIds.contains(mat.id);
                return _MaterialCard(
                  material: mat,
                  selectionMode: _selectionMode,
                  isSelected: isSelected,
                  onTap: () {
                    if (_selectionMode) {
                      _toggleSelection(mat.id);
                    } else {
                      final routeName = _isTemporary
                          ? 'temporary-material-detail'
                          : 'material-detail';
                      context.pushNamed(routeName,
                          pathParameters: {'id': mat.id.toString()});
                    }
                  },
                  onLongPress: () {
                    if (!_selectionMode) {
                      _enterSelectionMode(mat.id);
                    }
                  },
                );
              },
            ),
    );
  }

  Widget _buildShimmer() {
    return Shimmer.fromColors(
      baseColor: const Color(0xFF1E1E2E),
      highlightColor: const Color(0xFF2A2A3E),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 8,
        itemBuilder: (_, __) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          height: 100,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.library_books_outlined,
              size: 72, color: Colors.white24),
          const SizedBox(height: 16),
          Text(_isTemporary ? '还没有临时素材' : '还没有素材',
              style: const TextStyle(fontSize: 18, color: Colors.white54)),
          const SizedBox(height: 8),
          Text(_isTemporary ? '浏览网页时选择文本，通过"添加到Help to Learn"快速收藏' : '点击右上角 + 添加第一个素材',
              style: const TextStyle(fontSize: 14, color: Colors.white38)),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Colors.white60)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => _loadMaterials(refresh: true),
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }
}

// ─── Material Card Widget ─────────────────────────────────────────────────────

class _MaterialCard extends StatelessWidget {
  final MaterialModel material;
  final bool selectionMode;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _MaterialCard({
    required this.material,
    required this.selectionMode,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected ? cs.primary : const Color(0xFF2A2A3E),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              if (selectionMode)
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? cs.primary.withOpacity(0.2)
                        : Colors.white10,
                    borderRadius: BorderRadius.circular(12),
                    border: isSelected
                        ? Border.all(color: cs.primary, width: 2)
                        : null,
                  ),
                  child: Icon(
                      isSelected ? Icons.check : Icons.circle_outlined,
                      color: isSelected ? cs.primary : Colors.white38,
                      size: 22),
                )
              else
                _statusIcon(),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      material.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      children: [
                        _chip(material.language.toUpperCase()),
                        _chip(material.sourceType.name),
                        if (material.materialType == MaterialCategory.temporary)
                          _chip('临时'),
                        if (material.durationFormatted.isNotEmpty)
                          _chip(material.durationFormatted),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      timeago.format(material.createdAt, locale: 'zh'),
                      style: const TextStyle(
                          fontSize: 11, color: Colors.white38),
                    ),
                  ],
                ),
              ),
              if (!selectionMode)
                const Icon(Icons.chevron_right, color: Colors.white30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusIcon() {
    final (color, icon) = switch (material.status) {
      MaterialStatus.done => (Colors.green, Icons.check_circle),
      MaterialStatus.processing => (Colors.orange, Icons.sync),
      MaterialStatus.failed => (Colors.red, Icons.error),
      MaterialStatus.pending => (Colors.grey, Icons.schedule),
    };
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }

  Widget _chip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: const TextStyle(fontSize: 11, color: Colors.white54)),
    );
  }
}
