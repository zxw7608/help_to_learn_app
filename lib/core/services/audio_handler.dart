import 'dart:async';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import '../logging/app_logger.dart';
import '../models/segment.dart';
import '../services/cache_service.dart';

/// Custom AudioHandler for the audio_service package.
///
/// Handles:
/// - Sequential segment playback (auto-advance)
/// - Single segment playback
/// - Media notification controls including Anki button
/// - Prev/Next segment AND prev/next material navigation
class HelpToLearnAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  late AudioPlayer _player;

  List<SegmentModel> _segments = [];
  List<MediaItem> _materials = []; // For prev/next material navigation
  int _currentSegmentIndex = 0;
  int _currentMaterialIndex = 0;
  bool _sequentialMode = false;
  SegmentModel? _lastAttemptedSegment;
  bool _isRecovering = false;

  // Callbacks for UI to react to material navigation
  void Function(int materialIndex)? onMaterialChanged;
  void Function()? onRequestAnkiPush;

  AudioPlayer _createPlayer() {
    return AudioPlayer();
  }

  HelpToLearnAudioHandler() {
    _player = _createPlayer();
    _player.playbackEventStream.listen(_onPlaybackEvent, onError: _onStreamError);
    _player.playerStateStream.listen(_onPlayerStateChanged, onError: _onStreamError);
    AppLogger.info('AudioHandler initialized', tag: 'AudioHandler');
  }

  void _onStreamError(Object e, StackTrace st) async {
    AppLogger.error('Audio stream error caught: $e', tag: 'AudioHandler', error: e, stackTrace: st);
    if (_isRecovering) {
      AppLogger.warning('Already recovering, ignoring stream error.', tag: 'AudioHandler');
      return;
    }
    // OnePlus/Oppo Android 14 has an ExoPlayer bug where MP3 audio offload crashes on first play.
    // If we catch this PlatformException, we automatically retry loading and playing the segment.
    final errStr = e.toString();
    if (errStr.contains('PlatformException(2') ||
        errStr.contains('Unexpected runtime error') ||
        errStr.contains('IllegalStateException') ||
        errStr.contains('ERROR_CODE_')) {
      AppLogger.warning('Detected ExoPlayer crash! Attempting automatic recovery...', tag: 'AudioHandler');
      _isRecovering = true;
      try {
        await Future.delayed(const Duration(milliseconds: 300));
        try {
          await _player.stop();
          await _player.dispose();
        } catch (_) {}

        // Recreate the player to completely reset ExoPlayer's faulty state
        _player = _createPlayer();
        _player.playbackEventStream.listen(_onPlaybackEvent, onError: _onStreamError);
        _player.playerStateStream.listen(_onPlayerStateChanged, onError: _onStreamError);

        // Retry loading the file and playing using the saved segment
        final segmentToRecover = _lastAttemptedSegment;
        if (segmentToRecover != null) {
          AppLogger.info('Reloading segment ${segmentToRecover.id} for recovery', tag: 'AudioHandler');
          try {
            final path = await CacheService.instance.getAudioPath(segmentToRecover.id);
            await _player.setFilePath(path);
            mediaItem.add(MediaItem(
              id: segmentToRecover.id.toString(),
              title: segmentToRecover.text,
              album: mediaItem.value?.album ?? '',
              artist: segmentToRecover.translation ?? '',
              duration: segmentToRecover.duration != null
                  ? Duration(milliseconds: (segmentToRecover.duration! * 1000).round())
                  : null,
            ));
            _updatePlaybackState();
            await _player.play();
            AppLogger.info('Recovery successful!', tag: 'AudioHandler');
          } catch (e) {
            AppLogger.error('Error reloading segment during recovery: $e', tag: 'AudioHandler');
          }
        } else {
          AppLogger.warning('No segment available to recover.', tag: 'AudioHandler');
        }
      } catch (retryErr) {
        AppLogger.error('Recovery failed.', tag: 'AudioHandler', error: retryErr);
      } finally {
        _isRecovering = false;
      }
    }
  }

  // ─── Public API ─────────────────────────────────────────────────────────────

  Future<bool> loadMaterial({
    required List<SegmentModel> segments,
    required MediaItem materialItem,
    int startIndex = 0,
    bool sequential = true,
  }) async {
    AppLogger.info(
        'Loading material: "${materialItem.title}" with ${segments.length} segments',
        tag: 'AudioHandler');
    _segments = segments;
    _currentSegmentIndex = startIndex;
    _sequentialMode = sequential;

    // Register material in queue (for MediaSession album art etc.)
    mediaItem.add(materialItem);

    final ok = await _loadCurrentSegment();
    if (!ok) {
      AppLogger.warning('Failed to load initial segment for material',
          tag: 'AudioHandler');
    }
    return ok;
  }

  /// Set the list of all materials for prev/next material navigation.
  void setMaterialsList(List<MediaItem> materials, int currentIndex) {
    _materials = materials;
    _currentMaterialIndex = currentIndex;
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

  // ─── AudioHandler overrides ──────────────────────────────────────────────────

  @override
  Future<void> play() async {
    AppLogger.debug('Play: segment index=$_currentSegmentIndex', tag: 'AudioHandler');
    AppLogger.info('Before play(): processingState=${_player.processingState}, playing=${_player.playing}',
        tag: 'AudioHandler');
    try {
      await _player.setVolume(1.0);
      await _player.play();
      AppLogger.info('play() completed. playing=${_player.playing}', tag: 'AudioHandler');
    } catch (e, st) {
      AppLogger.error('Error during play(): $e', tag: 'AudioHandler', error: e, stackTrace: st);
      playbackState.add(playbackState.value.copyWith(
        processingState: AudioProcessingState.error,
        playing: false,
      ));
    }
  }

  @override
  Future<void> pause() async {
    AppLogger.debug('Pause', tag: 'AudioHandler');
    await _player.pause();
  }

  /// Force-stops playback and disposes the underlying player.
  /// Only call this when the app is being terminated.
  Future<void> performCleanup() async {
    AppLogger.info('performCleanup: stopping and disposing player', tag: 'AudioHandler');
    try { await _player.pause(); } catch (_) {}
    try { await _player.stop(); } catch (_) {}
    try { await _player.dispose(); } catch (_) {}
    try { await super.stop(); } catch (_) {}
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.idle,
    ));
  }

  @override
  Future<void> stop() async {
    AppLogger.debug('Stop', tag: 'AudioHandler');
    await super.stop();
    await _player.stop();
    _segments = [];
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.idle,
    ));
  }

  @override
  Future<void> skipToNext() async => _nextSegment();

  @override
  Future<void> skipToPrevious() async => _previousSegment();

  @override
  Future<void> seek(Duration position) async => _player.seek(position);

  @override
  Future<void> customAction(String name,
      [Map<String, dynamic>? extras]) async {
    AppLogger.info('Custom action: $name extras=$extras', tag: 'AudioHandler');
    switch (name) {
      case 'push_to_anki':
        onRequestAnkiPush?.call();
        break;
      case 'next_material':
        await _nextMaterial();
        break;
      case 'prev_material':
        await _previousMaterial();
        break;
    }
  }

  // ─── Internal ────────────────────────────────────────────────────────────────

  /// Loads the current segment's audio file into the player.
  /// Returns true if the segment was successfully loaded.
  Future<bool> _loadCurrentSegment() async {
    if (_segments.isEmpty) return false;
    final segment = _segments[_currentSegmentIndex];
    _lastAttemptedSegment = segment;
    AppLogger.debug(
        'Loading segment ${segment.id} (${_currentSegmentIndex + 1}/${_segments.length})',
        tag: 'AudioHandler');

    try {
      final path = await CacheService.instance.getAudioPath(segment.id);

      if (_segments.isEmpty || _currentSegmentIndex >= _segments.length || _segments[_currentSegmentIndex].id != segment.id) {
        AppLogger.debug('Segment changed while caching, aborting load', tag: 'AudioHandler');
        return false;
      }

      final file = File(path);
      final exists = await file.exists();
      final size = exists ? await file.length() : -1;
      AppLogger.info('File Path: $path | Exists: $exists | Size: $size bytes', tag: 'AudioHandler');

      if (!exists || size <= 0) {
        AppLogger.error('Audio file missing or empty for segment ${segment.id}',
            tag: 'AudioHandler');
        playbackState.add(playbackState.value.copyWith(
          processingState: AudioProcessingState.error,
          playing: false,
        ));
        return false;
      }

      final duration = await _player.setFilePath(path);
      AppLogger.info('setFilePath returned duration: $duration', tag: 'AudioHandler');

      mediaItem.add(MediaItem(
        id: segment.id.toString(),
        title: segment.text,
        album: mediaItem.value?.album ?? '',
        artist: segment.translation ?? '',
        duration: segment.duration != null
            ? Duration(milliseconds: (segment.duration! * 1000).round())
            : null,
      ));

      _updatePlaybackState();
      return true;
    } catch (e, st) {
      AppLogger.error('Failed to load segment ${segment.id}',
          tag: 'AudioHandler', error: e, stackTrace: st);
      playbackState.add(playbackState.value.copyWith(
        processingState: AudioProcessingState.error,
        playing: false,
      ));
      return false;
    }
  }

  void _onPlayerStateChanged(PlayerState state) {
    _updatePlaybackState();
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
    AppLogger.debug('Auto-advancing to next segment', tag: 'AudioHandler');
    if (_currentSegmentIndex < _segments.length - 1) {
      _currentSegmentIndex++;
      final ok = await _loadCurrentSegment();
      if (ok) await play();
    } else {
      AppLogger.info('Reached end of material', tag: 'AudioHandler');
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
  }

  Future<void> _nextMaterial() async {
    if (_currentMaterialIndex < _materials.length - 1) {
      _currentMaterialIndex++;
      AppLogger.info('Moving to next material index=$_currentMaterialIndex',
          tag: 'AudioHandler');
      onMaterialChanged?.call(_currentMaterialIndex);
    }
  }

  Future<void> _previousMaterial() async {
    if (_currentMaterialIndex > 0) {
      _currentMaterialIndex--;
      AppLogger.info('Moving to prev material index=$_currentMaterialIndex',
          tag: 'AudioHandler');
      onMaterialChanged?.call(_currentMaterialIndex);
    }
  }

  void _onPlaybackEvent(PlaybackEvent event) {
    _updatePlaybackState();
  }

  void _updatePlaybackState() {
    final playing = _player.playing;
    playbackState.add(playbackState.value.copyWith(
      controls: [
        // Prev material
        const MediaControl(
          androidIcon: 'drawable/ic_skip_previous',
          label: '上一素材',
          action: MediaAction.custom,
        ),
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        // Next material
        const MediaControl(
          androidIcon: 'drawable/ic_skip_next',
          label: '下一素材',
          action: MediaAction.custom,
        ),
        // Anki push
        const MediaControl(
          androidIcon: 'drawable/ic_style',
          label: '加入Anki',
          action: MediaAction.custom,
        ),
      ],
      androidCompactActionIndices: const [1, 2, 3],
      processingState: {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
    ));
  }

  @override
  Future<void> onTaskRemoved() async {
    AppLogger.info('Task removed (app swiped away)', tag: 'AudioHandler');
    try {
      await performCleanup();
    } catch (e, st) {
      AppLogger.error('Error during cleanup', tag: 'AudioHandler', error: e, stackTrace: st);
    }
    await super.onTaskRemoved();
  }
}
