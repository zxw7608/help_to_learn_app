import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../core/api/materials_api.dart';
import '../../core/models/material.dart';
import '../../core/logging/app_logger.dart';

class MaterialsListPage extends ConsumerStatefulWidget {
  const MaterialsListPage({super.key});

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

  String? _lastClipboardText;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    _loadMaterials();
    AppLogger.info('MaterialsListPage opened', tag: 'MaterialsList');
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

      // Check if it looks like a URL or substantial text
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
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
                  style: const TextStyle(fontSize: 13, color: Colors.white70)),
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
      final result = await materialsApi.list(page: _page, size: 20);
      setState(() {
        _materials = refresh ? result.items : [..._materials, ...result.items];
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

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('素材库'),
            if (_total > 0)
              Text('共 $_total 个素材',
                  style: const TextStyle(
                      fontSize: 12, color: Colors.white54)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: '添加素材',
            onPressed: () => context.pushNamed('add-material'),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return _buildShimmer();
    if (_error != null && _materials.isEmpty) return _buildError();

    return RefreshIndicator(
      onRefresh: () => _loadMaterials(refresh: true),
      child: _materials.isEmpty
          ? _buildEmpty()
          : ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              itemCount: _materials.length + (_loadingMore ? 1 : 0),
              itemBuilder: (ctx, i) {
                if (i == _materials.length) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return _MaterialCard(
                  material: _materials[i],
                  onTap: () => context.pushNamed('material-detail',
                      pathParameters: {'id': _materials[i].id.toString()}),
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
          const Text('还没有素材',
              style: TextStyle(fontSize: 18, color: Colors.white54)),
          const SizedBox(height: 8),
          const Text('点击右上角 + 添加第一个素材',
              style: TextStyle(fontSize: 14, color: Colors.white38)),
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
  final VoidCallback onTap;

  const _MaterialCard({required this.material, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Status indicator
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
