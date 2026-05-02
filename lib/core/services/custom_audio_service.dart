import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../logging/app_logger.dart';
import '../models/segment.dart';
import 'cache_service.dart';

class PlaybackInfo {
  final bool playing;
  final String title;
  final String subtitle;
  final Duration? duration;
  final Duration position;
  final bool hasPrevMaterial;
  final bool hasNextMaterial;
  final bool hasPrevSegment;
  final bool hasNextSegment;

  const PlaybackInfo({
    this.playing = false,
    this.title = '',
    this.subtitle = '',
    this.duration,
    this.position = Duration.zero,
    this.hasPrevMaterial = false,
    this.hasNextMaterial = false,
    this.hasPrevSegment = false,
    this.hasNextSegment = false,
  });
}

class CustomAudioService {
  static const _channel = MethodChannel('help_to_learn/audio');

  late AudioPlayer _player;
  List<SegmentModel> _segments = [];
  List<MapEntry<int, String>> _materials = []; // id -> title
  int _currentSegmentIndex = 0;
  int _currentMaterialIndex = -1;
  bool _sequentialMode = false;
  SegmentModel? _lastAttemptedSegment;
  bool _isRecovering = false;
  bool _foregroundStarted = false;

  // Observable state for UI
  final _playbackInfo = ValueNotifier<PlaybackInfo>(const PlaybackInfo());
  ValueNotifier<PlaybackInfo> get playbackInfo => _playbackInfo;

  String? _currentSegmentId;
  String? get currentSegmentId => _currentSegmentId;
  SegmentModel? get currentSegment =>
      _segments.isNotEmpty && _currentSegmentIndex < _segments.length
          ? _segments[_currentSegmentIndex]
          : null;
  String get currentMaterialId =>
      _currentMaterialIndex >= 0 && _currentMaterialIndex < _materials.length
          ? _materials[_currentMaterialIndex].key.toString()
          : '';

  // Callbacks
  void Function(int materialIndex)? onMaterialChanged;
  void Function()? onRequestAnkiPush;

  CustomAudioService() {
    _player = _createPlayer();
    _player.playbackEventStream.listen(_onPlaybackEvent, onError: _onStreamError);
    _player.playerStateStream.listen(_onPlayerStateChanged, onError: _onStreamError);
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  AudioPlayer _createPlayer() => AudioPlayer();

  // ─── MethodChannel Handler (Android → Flutter) ──────────────────────────────

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onButtonPress':
        _handleButtonPress(call.arguments as String);
      case 'onMediaButton':
        _handleMediaButton(call.arguments as String);
      case 'onNotificationDeleted':
        await performCleanup();
      case 'onSeekTo':
        final ms = (call.arguments as Map)['positionMs'] as int;
        await seek(Duration(milliseconds: ms));
    }
  }

  void _handleButtonPress(String action) {
    switch (action) {
      case 'play_pause':
        if (_player.playing) {
          pause();
        } else {
          play();
        }
      case 'prev_segment':
        _previousSegment();
      case 'next_segment':
        _nextSegment();
      case 'prev_material':
        _previousMaterial();
      case 'next_material':
        _nextMaterial();
      case 'anki':
        onRequestAnkiPush?.call();
    }
  }

  void _handleMediaButton(String action) {
    switch (action) {
      case 'play':
        play();
      case 'pause':
        pause();
      case 'next':
        _nextSegment();
      case 'prev':
        _previousSegment();
    }
  }

  // ─── Public API ─────────────────────────────────────────────────────────────

  Future<bool> loadMaterial({
    required List<SegmentModel> segments,
    required String materialTitle,
    int materialId = 0,
    int startIndex = 0,
    bool sequential = true,
  }) async {
    _segments = segments;
    _currentSegmentIndex = startIndex;
    _sequentialMode = sequential;
    // Find and set current material index
    _currentMaterialIndex =
        _materials.indexWhere((e) => e.key == materialId);
    if (_currentMaterialIndex == -1) _currentMaterialIndex = 0;

    final ok = await _loadCurrentSegment();
    if (!ok) {
      AppLogger.warning('Failed to load initial segment', tag: 'AudioService');
    }
    return ok;
  }

  void setMaterialsList(List<MapEntry<int, String>> materials, int currentId) {
    _materials = materials;
    _currentMaterialIndex = _materials.indexWhere((e) => e.key == currentId);
  }

  void setCurrentMaterialIndex(int materialId) {
    _currentMaterialIndex = _materials.indexWhere((e) => e.key == materialId);
  }

  Future<void> playSegment(int index) async {
    if (index < 0 || index >= _segments.length) return;
    _currentSegmentIndex = index;
    _sequentialMode = false;
    final ok = await _loadCurrentSegment();
    if (ok) await play();
  }

  Future<void> startSequential(int startIndex) async {
    _currentSegmentIndex = startIndex;
    _sequentialMode = true;
    final ok = await _loadCurrentSegment();
    if (ok) await play();
  }

  Future<void> play() async {
    try {
      await _player.play();
      await _sendNotification();
    } catch (e, st) {
      AppLogger.error('Error during play()', tag: 'AudioService', error: e, stackTrace: st);
    }
  }

  Future<void> pause() async {
    await _player.pause();
    await _sendNotification();
  }

  Future<void> stop() async {
    _foregroundStarted = false;
    await _player.stop();
    _segments = [];
    await _channel.invokeMethod('stopForeground');
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
    await _sendNotification();
  }

  Future<void> performCleanup() async {
    _foregroundStarted = false;
    AppLogger.info('performCleanup', tag: 'AudioService');
    try { await _player.pause(); } catch (_) {}
    try { await _player.stop(); } catch (_) {}
    try { await _player.dispose(); } catch (_) {}
    try { await _channel.invokeMethod('stopForeground'); } catch (_) {}
  }

  // ─── Internal ────────────────────────────────────────────────────────────────

  Future<bool> _loadCurrentSegment() async {
    if (_segments.isEmpty) return false;
    final segment = _segments[_currentSegmentIndex];
    _lastAttemptedSegment = segment;
    _currentSegmentId = segment.id.toString();

    try {
      final path = await CacheService.instance.getAudioPath(segment.id);

      if (_segments.isEmpty ||
          _currentSegmentIndex >= _segments.length ||
          _segments[_currentSegmentIndex].id != segment.id) {
        return false;
      }

      final file = File(path);
      final exists = await file.exists();
      final size = exists ? await file.length() : -1;

      if (!exists || size <= 0) {
        AppLogger.error('Audio file missing or empty for segment ${segment.id}',
            tag: 'AudioService');
        return false;
      }

      await _player.setFilePath(path);
      return true;
    } catch (e, st) {
      AppLogger.error('Failed to load segment ${segment.id}',
          tag: 'AudioService', error: e, stackTrace: st);
      return false;
    }
  }

  void _onPlayerStateChanged(PlayerState state) {
    _sendNotification();
    if (state.processingState == ProcessingState.completed) {
      if (_sequentialMode) {
        _autoAdvance();
      } else {
        _player.pause();
        _player.seek(Duration.zero);
      }
    }
  }

  Future<void> _autoAdvance() async {
    if (_currentSegmentIndex < _segments.length - 1) {
      _currentSegmentIndex++;
      final ok = await _loadCurrentSegment();
      if (ok) await play();
    } else {
      AppLogger.info('Reached end of material', tag: 'AudioService');
      await stop();
    }
  }

  Future<void> _nextSegment() async {
    if (_currentSegmentIndex < _segments.length - 1) {
      _currentSegmentIndex++;
      final ok = await _loadCurrentSegment();
      if (ok) await play();
    }
  }

  Future<void> _previousSegment() async {
    if (_player.position.inSeconds > 3) {
      await _player.seek(Duration.zero);
    } else if (_currentSegmentIndex > 0) {
      _currentSegmentIndex--;
      final ok = await _loadCurrentSegment();
      if (ok) await play();
    }
    await _sendNotification();
  }

  Future<void> _nextMaterial() async {
    if (_currentMaterialIndex < _materials.length - 1) {
      _currentMaterialIndex++;
      AppLogger.info('Moving to next material index=$_currentMaterialIndex',
          tag: 'AudioService');
      onMaterialChanged?.call(_currentMaterialIndex);
    }
  }

  Future<void> _previousMaterial() async {
    if (_currentMaterialIndex > 0) {
      _currentMaterialIndex--;
      AppLogger.info('Moving to prev material index=$_currentMaterialIndex',
          tag: 'AudioService');
      onMaterialChanged?.call(_currentMaterialIndex);
    }
  }

  void _onPlaybackEvent(PlaybackEvent event) {
    _sendNotification();
  }

  Future<void> _sendNotification() async {
    final playing = _player.playing;
    final segment = _segments.isNotEmpty &&
            _currentSegmentIndex < _segments.length
        ? _segments[_currentSegmentIndex]
        : null;

    final title = segment?.text ?? 'Help To Learn';
    final subtitle = segment?.translation ?? '';
    final segDuration = segment?.duration;
    final playerDuration = _player.duration;
    final duration = segDuration != null
        ? Duration(milliseconds: (segDuration * 1000).round())
        : playerDuration;

    final info = PlaybackInfo(
      playing: playing,
      title: title,
      subtitle: subtitle,
      duration: duration,
      position: _player.position,
      hasPrevMaterial: _currentMaterialIndex > 0,
      hasNextMaterial: _currentMaterialIndex < _materials.length - 1,
      hasPrevSegment: _currentSegmentIndex > 0 ||
          _player.position.inSeconds > 3,
      hasNextSegment: _currentSegmentIndex < _segments.length - 1,
    );
    final payload = <String, dynamic>{
      'title': title,
      'subtitle': subtitle,
      'playing': playing,
      'durationMs': duration?.inMilliseconds ?? 0,
      'positionMs': _player.position.inMilliseconds,
      'hasPrevMaterial': info.hasPrevMaterial,
      'hasNextMaterial': info.hasNextMaterial,
      'hasPrevSegment': info.hasPrevSegment,
      'hasNextSegment': info.hasNextSegment,
    };
    _playbackInfo.value = info;

    if (!_foregroundStarted) {
      _foregroundStarted = true;
      await _channel.invokeMethod('startForeground', payload);
    } else {
      await _channel.invokeMethod('updateNotification', payload);
    }
  }

  void _onStreamError(Object e, StackTrace st) async {
    AppLogger.error('Audio stream error: $e', tag: 'AudioService', error: e, stackTrace: st);
    if (_isRecovering) return;
    final errStr = e.toString();
    if (errStr.contains('PlatformException(2') ||
        errStr.contains('Unexpected runtime error') ||
        errStr.contains('IllegalStateException') ||
        errStr.contains('ERROR_CODE_')) {
      AppLogger.warning('Detected ExoPlayer crash! Attempting recovery...', tag: 'AudioService');
      _isRecovering = true;
      try {
        await Future.delayed(const Duration(milliseconds: 300));
        try {
          await _player.stop();
          await _player.dispose();
        } catch (_) {}
        _player = _createPlayer();
        _player.playbackEventStream.listen(_onPlaybackEvent, onError: _onStreamError);
        _player.playerStateStream.listen(_onPlayerStateChanged, onError: _onStreamError);

        final seg = _lastAttemptedSegment;
        if (seg != null) {
          try {
            final path = await CacheService.instance.getAudioPath(seg.id);
            await _player.setFilePath(path);
            await _player.play();
          } catch (e) {
            AppLogger.error('Recovery error', tag: 'AudioService', error: e);
          }
        }
      } finally {
        _isRecovering = false;
      }
    }
  }
}
