import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/logging/app_logger.dart';

class LogViewerPage extends StatefulWidget {
  const LogViewerPage({super.key});

  @override
  State<LogViewerPage> createState() => _LogViewerPageState();
}

class _LogViewerPageState extends State<LogViewerPage> {
  final _searchCtrl = TextEditingController();
  Level? _filterLevel;
  List<LogEvent> _logs = [];
  List<LogEvent> _filtered = [];
  bool _autoScroll = false;
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _logs = AppLogger.recentLogs;
    _filtered = _logs;
    _searchCtrl.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _applyFilter() {
    final query = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = _logs.where((e) {
        if (_filterLevel != null && e.level != _filterLevel) return false;
        if (query.isNotEmpty && !e.message.toString().toLowerCase().contains(query)) {
          return false;
        }
        return true;
      }).toList();
    });
  }

  void _refresh() {
    setState(() {
      _logs = AppLogger.recentLogs;
    });
    _applyFilter();
  }

  Color _levelColor(Level level) {
    switch (level) {
      case Level.trace:
        return Colors.grey;
      case Level.debug:
        return Colors.blue;
      case Level.info:
        return Colors.green;
      case Level.warning:
        return Colors.orange;
      case Level.error:
        return Colors.red;
      case Level.fatal:
        return Colors.purple;
      default:
        return Colors.white54;
    }
  }

  String _levelLabel(Level level) {
    switch (level) {
      case Level.trace:
        return 'TRACE';
      case Level.debug:
        return 'DEBUG';
      case Level.info:
        return 'INFO';
      case Level.warning:
        return 'WARN';
      case Level.error:
        return 'ERROR';
      case Level.fatal:
        return 'FATAL';
      default:
        return '?';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('日志 (${_filtered.length})'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
            tooltip: '刷新',
          ),
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: '分享日志文件',
            onPressed: () async {
              final path = AppLogger.currentLogFilePath;
              if (path != null && File(path).existsSync()) {
                await Share.shareXFiles([XFile(path)], subject: '应用日志');
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('日志文件不存在')),
                );
              }
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(100),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Column(
              children: [
                // Search bar
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: '搜索日志...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        vertical: 8, horizontal: 12),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () {
                              _searchCtrl.clear();
                              _applyFilter();
                            },
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 6),
                // Level filter chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _FilterChip(
                          label: 'ALL',
                          selected: _filterLevel == null,
                          color: Colors.white,
                          onTap: () {
                            setState(() => _filterLevel = null);
                            _applyFilter();
                          }),
                      for (final level in [
                        Level.info,
                        Level.warning,
                        Level.error,
                        Level.fatal,
                        Level.debug,
                      ])
                        _FilterChip(
                          label: _levelLabel(level),
                          selected: _filterLevel == level,
                          color: _levelColor(level),
                          onTap: () {
                            setState(() => _filterLevel = level);
                            _applyFilter();
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: _filtered.isEmpty
          ? const Center(
              child: Text('无日志', style: TextStyle(color: Colors.white38)))
          : ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.all(8),
              itemCount: _filtered.length,
              itemBuilder: (ctx, i) {
                final event = _filtered[_filtered.length - 1 - i]; // newest first
                return _LogEntry(
                  event: event,
                  levelColor: _levelColor(event.level),
                  levelLabel: _levelLabel(event.level),
                );
              },
            ),
    );
  }
}

class _LogEntry extends StatelessWidget {
  final LogEvent event;
  final Color levelColor;
  final String levelLabel;

  const _LogEntry({
    required this.event,
    required this.levelColor,
    required this.levelLabel,
  });

  @override
  Widget build(BuildContext context) {
    final text = event.message.toString();
    final hasError = event.error != null;

    return GestureDetector(
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: text));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已复制到剪切板'), duration: Duration(seconds: 1)),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: hasError
              ? Colors.red.withOpacity(0.05)
              : const Color(0xFF1E1E2E),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: hasError ? Colors.red.withOpacity(0.2) : Colors.transparent,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: levelColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    levelLabel,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: levelColor),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    text,
                    style: const TextStyle(fontSize: 12, color: Color(0xDEFFFFFF)),
                    maxLines: hasError ? 5 : 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (event.error != null) ...[
              const SizedBox(height: 4),
              Text(
                '${event.error}',
                style:
                    const TextStyle(fontSize: 11, color: Colors.redAccent),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.2) : const Color(0xFF2A2A3E),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: selected ? color.withOpacity(0.6) : Colors.transparent),
        ),
        child: Text(
          label,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: selected ? color : Colors.white38),
        ),
      ),
    );
  }
}
