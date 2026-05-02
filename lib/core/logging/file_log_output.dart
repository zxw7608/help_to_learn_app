import 'dart:io';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';

/// Writes log entries to daily-rotating files.
/// Retains [retainDays] days of logs; older files are auto-deleted.
class FileLogOutput extends LogOutput {
  final Directory logDir;
  final int retainDays;

  IOSink? _currentSink;
  String? _currentDate;
  String? currentFilePath;

  FileLogOutput({required this.logDir, this.retainDays = 7});

  Future<void> init() async {
    await _rotatIfNeeded();
    await _pruneOldLogs();
  }

  @override
  void output(OutputEvent event) {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    if (_currentDate != today) {
      // Synchronously fire the async rotation, but don't write to the closing sink
      _rotatIfNeeded();
      // Drop log to file while rotating to avoid "bound to stream" error
      return; 
    }
    final lines = event.lines.join('\n');
    _currentSink?.writeln(lines);
  }

  @override
  Future<void> destroy() async {
    await _currentSink?.flush();
    await _currentSink?.close();
    _currentSink = null;
  }

  Future<void> _rotatIfNeeded() async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    if (_currentDate == today) return;

    // Close previous
    await _currentSink?.flush();
    await _currentSink?.close();

    final filePath = '${logDir.path}/app_$today.log';
    currentFilePath = filePath;
    final file = File(filePath);
    _currentSink = file.openWrite(mode: FileMode.append);
    _currentDate = today;

    _currentSink!.writeln(
        '\n=== Session started: ${DateTime.now().toIso8601String()} ===\n');
  }

  Future<void> _pruneOldLogs() async {
    final cutoff = DateTime.now().subtract(Duration(days: retainDays));
    final files = logDir.listSync().whereType<File>();
    for (final file in files) {
      try {
        final name = file.uri.pathSegments.last;
        // Expected pattern: app_YYYY-MM-DD.log
        if (name.startsWith('app_') && name.endsWith('.log')) {
          final dateStr = name.substring(4, 14);
          final date = DateTime.tryParse(dateStr);
          if (date != null && date.isBefore(cutoff)) {
            await file.delete();
          }
        }
      } catch (_) {
        // Ignore individual file errors during pruning
      }
    }
  }
}
