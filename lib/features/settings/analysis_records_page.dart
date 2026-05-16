import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/analysis_api.dart';
import '../../core/models/analysis_record.dart';

class AnalysisRecordsPage extends StatefulWidget {
  const AnalysisRecordsPage({super.key});

  @override
  State<AnalysisRecordsPage> createState() => _AnalysisRecordsPageState();
}

class _AnalysisRecordsPageState extends State<AnalysisRecordsPage> {
  List<AnalysisRecord> _records = [];
  bool _loading = true;
  int _page = 1;
  bool _hasMore = true;
  static const _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final records = await analysisApi.list(page: _page, size: _pageSize);
      if (mounted) {
        setState(() {
          if (_page == 1) {
            _records = records;
          } else {
            _records.addAll(records);
          }
          _hasMore = records.length >= _pageSize;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _loadMore() {
    if (_loading || !_hasMore) return;
    _page++;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 解析记录'),
      ),
      body: _loading && _records.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _records.isEmpty
              ? const Center(
                  child: Text('暂无 AI 解析记录',
                      style: TextStyle(color: Colors.white54)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _records.length + (_hasMore ? 1 : 0),
                  itemBuilder: (ctx, i) {
                    if (i >= _records.length) {
                      // Load more indicator
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _loadMore();
                      });
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }

                    final rec = _records[i];
                    return Card(
                      color: const Color(0xFF1E1E2E),
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: rec.segmentId != null
                            ? () => context.push('/material/${rec.segmentId}')
                            : null,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.white10,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '#${rec.segmentId}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.white38,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    _formatDate(rec.createdAt),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.white38,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                rec.selectedPhrase,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF6f42c1),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxHeight: 200),
                                child: SingleChildScrollView(
                                  child: Text(
                                    rec.analysis,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13,
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    return '${local.year}-${_pad(local.month)}-${_pad(local.day)} '
        '${_pad(local.hour)}:${_pad(local.minute)}';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}
