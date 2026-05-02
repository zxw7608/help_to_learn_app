import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';

import 'file_log_output.dart';

/// Global application logger.
///
/// Usage:
///   AppLogger.info('Something happened', tag: 'MyClass');
///   AppLogger.error('Oops', error: e, stackTrace: st, tag: 'NetworkService');
class AppLogger {
  static Logger? _logger;
  static FileLogOutput? _fileOutput;
  static final List<LogEvent> _recentLogs = [];
  static const int _maxRecentLogs = 500;

  static Future<void> init() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final logDir = Directory('${docsDir.path}/logs');
    await logDir.create(recursive: true);

    _fileOutput = FileLogOutput(logDir: logDir, retainDays: 7);
    await _fileOutput!.init();

    _logger = Logger(
      level: kDebugMode ? Level.verbose : Level.info,
      printer: PrefixPrinter(
        PrettyPrinter(
          methodCount: 2,
          errorMethodCount: 8,
          lineLength: 120,
          colors: false,
          printEmojis: true,
          dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
        ),
      ),
      output: MultiOutput([
        ConsoleOutput(),
        _fileOutput!,
        _InMemoryOutput(_recentLogs, _maxRecentLogs),
      ]),
    );
  }

  /// Returns recent in-memory log events for the in-app log viewer.
  static List<LogEvent> get recentLogs => List.unmodifiable(_recentLogs);

  /// Returns path to the current log file.
  static String? get currentLogFilePath => _fileOutput?.currentFilePath;

  static void verbose(String message, {String? tag, Object? data}) =>
      _log(Level.trace, message, tag: tag, data: data);

  static void debug(String message, {String? tag, Object? data}) =>
      _log(Level.debug, message, tag: tag, data: data);

  static void info(String message, {String? tag, Object? data}) =>
      _log(Level.info, message, tag: tag, data: data);

  static void warning(String message,
          {String? tag, Object? error, StackTrace? stackTrace}) =>
      _log(Level.warning, message,
          tag: tag, error: error, stackTrace: stackTrace);

  static void error(String message,
          {String? tag, Object? error, StackTrace? stackTrace}) =>
      _log(Level.error, message,
          tag: tag, error: error, stackTrace: stackTrace);

  static void fatal(String message,
          {String? tag, Object? error, StackTrace? stackTrace}) =>
      _log(Level.fatal, message,
          tag: tag, error: error, stackTrace: stackTrace);

  /// Called by zone error handler for top-level unhandled errors
  static void onError(Object error, StackTrace stackTrace) {
    fatal('Unhandled async error',
        error: error, stackTrace: stackTrace, tag: 'ZonedGuarded');
  }

  static void _log(
    Level level,
    String message, {
    String? tag,
    Object? data,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (_logger == null) {
      // Fallback if init not called yet
      debugPrint('[${level.name.toUpperCase()}]${tag != null ? '[$tag]' : ''} $message');
      return;
    }
    final prefix = tag != null ? '[$tag] ' : '';
    final fullMessage = data != null ? '$prefix$message\n$data' : '$prefix$message';
    _logger!.log(level, fullMessage, error: error, stackTrace: stackTrace);
  }
}

// ─── In-Memory Output ────────────────────────────────────────────────────────

class _InMemoryOutput extends LogOutput {
  final List<LogEvent> _buffer;
  final int _maxSize;

  _InMemoryOutput(this._buffer, this._maxSize);

  @override
  void output(OutputEvent event) {
    if (_buffer.length >= _maxSize) {
      _buffer.removeAt(0);
    }
    _buffer.add(event.origin);
  }
}
