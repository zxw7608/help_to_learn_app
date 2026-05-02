import 'dart:convert';
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/materials_api.dart';
import '../logging/app_logger.dart';
import '../models/playlist.dart';
import '../models/segment.dart';
import 'custom_audio_service.dart';

const _prefsKey = 'playlist_data';

final playlistManagerProvider =
    NotifierProvider<PlaylistManager, PlaylistState>(PlaylistManager.new);

class PlaylistManager extends Notifier<PlaylistState> {
  static CustomAudioService? _audioService;

  static void setAudioService(CustomAudioService service) {
    _audioService = service;
  }

  CustomAudioService get _audio => _audioService!;

  void Function(int materialId)? onMaterialSwitched;

  @override
  PlaylistState build() {
    _wireAudioCallbacks();
    _loadFromPrefs();
    return const PlaylistState();
  }

  // ─── Audio Callbacks ──────────────────────────────────────────────────────

  void _wireAudioCallbacks() {
    _audio.onMaterialFinished = () => _handleMaterialFinished();
    _audio.onPlaylistNav = (bool next) => _navigatePlaylist(next);
    _audio.onModeCycle = () => _cyclePlayMode();
  }

  void _cyclePlayMode() {
    // Cycle segment mode first, then material mode, then playlist loop
    final segModes = SegmentPlayMode.values;
    final matModes = MaterialPlayMode.values;
    final nextSeg = (state.segmentMode.index + 1) % segModes.length;
    if (nextSeg != 0) {
      setSegmentMode(segModes[nextSeg]);
    } else {
      final nextMat = (state.materialMode.index + 1) % matModes.length;
      if (nextMat != 0) {
        setMaterialMode(matModes[nextMat]);
      } else {
        togglePlaylistLoop();
      }
    }
  }

  Future<void> _handleMaterialFinished() async {
    final state = this.state;
    if (state.isEmpty) return;

    final nextIndex = _resolveNextMaterial(state);
    if (nextIndex == null) {
      if (state.playlistLoop && state.entries.isNotEmpty) {
        await _playMaterialAtIndex(0);
      } else {
        await _audio.pause();
        AppLogger.info('Playlist finished', tag: 'PlaylistManager');
      }
      return;
    }
    final targetId = state.entries[nextIndex].materialId;
    await _playMaterialAtIndex(nextIndex);
    onMaterialSwitched?.call(targetId);
  }

  int? _resolveNextMaterial(PlaylistState state) {
    switch (state.materialMode) {
      case MaterialPlayMode.sequential:
        if (state.hasNext) return state.currentIndex + 1;
        return null;
      case MaterialPlayMode.random:
        if (state.entries.length <= 1) return null;
        final rng = Random();
        int next;
        do {
          next = rng.nextInt(state.entries.length);
        } while (next == state.currentIndex && state.entries.length > 1);
        return next;
      case MaterialPlayMode.singleLoop:
        return state.currentIndex;
    }
  }

  Future<void> _navigatePlaylist(bool next) async {
    final state = this.state;
    if (state.isEmpty) return;
    switch (state.materialMode) {
      case MaterialPlayMode.sequential:
        if (next && state.hasNext) {
          await _playMaterialAtIndex(state.currentIndex + 1);
        } else if (!next && state.hasPrev) {
          await _playMaterialAtIndex(state.currentIndex - 1);
        }
        break;
      case MaterialPlayMode.random:
        if (state.entries.length <= 1) break;
        final rng = Random();
        int idx;
        do {
          idx = rng.nextInt(state.entries.length);
        } while (idx == state.currentIndex && state.entries.length > 1);
        await _playMaterialAtIndex(idx);
        break;
      case MaterialPlayMode.singleLoop:
        await _playMaterialAtIndex(state.currentIndex);
        break;
    }
  }

  Future<void> _playMaterialAtIndex(int index) async {
    if (index < 0 || index >= state.entries.length) return;
    final entry = state.entries[index];

    if (entry.segments == null || entry.segments!.isEmpty) {
      await _fetchSegments(entry);
    }
    if (entry.segments == null || entry.segments!.isEmpty) {
      AppLogger.warning('No segments for material ${entry.materialId}',
          tag: 'PlaylistManager');
      if (state.materialMode != MaterialPlayMode.singleLoop && state.hasNext) {
        state = state.copyWith(currentIndex: index + 1);
        await _handleMaterialFinished();
      }
      return;
    }

    state = state.copyWith(currentIndex: index);

    final segs = entry.segments!;
    final startIdx = state.segmentMode == SegmentPlayMode.random && segs.isNotEmpty
        ? Random().nextInt(segs.length)
        : 0;

    await _audio.loadMaterial(
      segments: segs,
      materialTitle: entry.title,
      materialId: entry.materialId,
      startIndex: startIdx,
      sequential: true,
    );
    _audio.setSegmentPlayMode(state.segmentMode);
    _syncPlaybackInfo();
    await _audio.play();
  }

  // ─── Public API ───────────────────────────────────────────────────────────

  Future<void> addMaterials(List<int> ids, {bool playNow = false}) async {
    if (ids.isEmpty) return;
    final existingIds = state.entries.map((e) => e.materialId).toSet();
    final newIds = ids.where((id) => !existingIds.contains(id)).toList();
    if (newIds.isEmpty && !playNow) return;

    final newEntries = <PlaylistEntry>[];
    for (final id in newIds) {
      try {
        final mat = await materialsApi.get(id);
        newEntries.add(PlaylistEntry(
          materialId: mat.id,
          title: mat.title,
          language: mat.language,
          status: mat.status,
        ));
      } catch (e) {
        AppLogger.warning('Failed to fetch material $id for playlist',
            tag: 'PlaylistManager');
      }
    }

    final allEntries = [...state.entries, ...newEntries];

    if (playNow) {
      final firstId = ids.first;
      final playIndex = allEntries.indexWhere((e) => e.materialId == firstId);
      state = state.copyWith(
        entries: allEntries,
        currentIndex: playIndex >= 0 ? playIndex : allEntries.length - 1,
      );
      await _playMaterialAtIndex(state.currentIndex);
    } else {
      state = state.copyWith(entries: allEntries);
    }
    _saveToPrefs();
  }

  void removeMaterial(int materialId) {
    final wasPlaying =
        state.hasCurrent && state.entries[state.currentIndex].materialId == materialId;
    final newEntries =
        state.entries.where((e) => e.materialId != materialId).toList();

    if (wasPlaying) {
      _audio.stop();
    }

    int newIndex = state.currentIndex;
    if (newEntries.isEmpty) {
      newIndex = -1;
    } else if (newIndex >= newEntries.length) {
      newIndex = newEntries.length - 1;
    }

    state = state.copyWith(entries: newEntries, currentIndex: newIndex);
    _syncPlaybackInfo();
    _saveToPrefs();

    if (wasPlaying && newIndex >= 0) {
      _playMaterialAtIndex(newIndex);
    }
  }

  void removeMaterialAt(int index) {
    if (index < 0 || index >= state.entries.length) return;
    removeMaterial(state.entries[index].materialId);
  }

  void reorder(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    final entries = List<PlaylistEntry>.from(state.entries);
    final item = entries.removeAt(oldIndex);
    final adjustedNew = newIndex > oldIndex ? newIndex - 1 : newIndex;
    entries.insert(adjustedNew.clamp(0, entries.length), item);

    int newCurrent = state.currentIndex;
    if (state.currentIndex == oldIndex) {
      newCurrent = adjustedNew.clamp(0, entries.length - 1);
    } else if (state.currentIndex > oldIndex && state.currentIndex <= newIndex) {
      newCurrent--;
    } else if (state.currentIndex < oldIndex && state.currentIndex >= newIndex) {
      newCurrent++;
    }

    state = state.copyWith(entries: entries, currentIndex: newCurrent);
    _syncPlaybackInfo();
    _saveToPrefs();
  }

  void clear() {
    _audio.stop();
    state = const PlaylistState();
    _saveToPrefs();
  }

  void setMaterialMode(MaterialPlayMode mode) {
    state = state.copyWith(materialMode: mode);
    _syncPlaybackInfo();
    _saveToPrefs();
  }

  void setSegmentMode(SegmentPlayMode mode) {
    state = state.copyWith(segmentMode: mode);
    _audio.setSegmentPlayMode(mode);
    _syncPlaybackInfo();
    _saveToPrefs();
  }

  void togglePlaylistLoop() {
    state = state.copyWith(playlistLoop: !state.playlistLoop);
    _syncPlaybackInfo();
    _saveToPrefs();
  }

  void cycleMaterialMode() {
    final modes = MaterialPlayMode.values;
    final nextIdx = (state.materialMode.index + 1) % modes.length;
    setMaterialMode(modes[nextIdx]);
  }

  void cycleSegmentMode() {
    final modes = SegmentPlayMode.values;
    final nextIdx = (state.segmentMode.index + 1) % modes.length;
    setSegmentMode(modes[nextIdx]);
  }

  Future<void> playAtIndex(int index) async {
    if (index < 0 || index >= state.entries.length) return;
    await _playMaterialAtIndex(index);
  }

  Future<void> playFromCurrent() async {
    if (state.isEmpty) return;
    if (!state.hasCurrent) {
      state = state.copyWith(currentIndex: 0);
    }
    await _playMaterialAtIndex(state.currentIndex);
  }

  Future<void> playFromStart() async {
    if (state.isEmpty) return;
    await _playMaterialAtIndex(0);
  }

  // ─── Internal ──────────────────────────────────────────────────────────────

  Future<void> _fetchSegments(PlaylistEntry entry) async {
    try {
      final segsRaw = await materialsApi.getSegmentsRaw(entry.materialId);
      entry.segments = segsRaw.map(SegmentModel.fromJson).toList();
    } catch (e) {
      AppLogger.error('Failed to fetch segments for material ${entry.materialId}',
          tag: 'PlaylistManager', error: e);
      entry.segments = [];
    }
  }

  void _syncPlaybackInfo() {
    final current = state.current;
    _audio.updatePlaylistInfo(
      playlistLabel: state.isEmpty
          ? ''
          : '素材 ${state.currentIndex + 1}/${state.entries.length}',
      materialTitle: current?.title ?? '',
      materialId: current?.materialId ?? 0,
      hasPrevPlaylist: state.hasPrev,
      hasNextPlaylist: state.hasNext,
      modeLabel:
          '${state.materialMode.shortLabel}·${state.segmentMode.shortLabel}${state.playlistLoop ? "·循环" : ""}',
    );
  }

  // ─── Persistence ──────────────────────────────────────────────────────────

  Future<void> _saveToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = {
        'entries': state.entries.map((e) => e.toJson()).toList(),
        'currentIndex': state.currentIndex,
        'materialMode': state.materialMode.index,
        'segmentMode': state.segmentMode.index,
        'playlistLoop': state.playlistLoop,
      };
      await prefs.setString(_prefsKey, jsonEncode(data));
    } catch (e) {
      AppLogger.warning('Failed to save playlist', tag: 'PlaylistManager');
    }
  }

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final entries = (data['entries'] as List)
          .map((e) => PlaylistEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      state = state.copyWith(
        entries: entries,
        currentIndex: (data['currentIndex'] as int? ?? -1)
            .clamp(-1, entries.length - 1),
        materialMode: MaterialPlayMode.values[(data['materialMode'] as int? ?? 0)
            .clamp(0, MaterialPlayMode.values.length - 1)],
        segmentMode: SegmentPlayMode.values[(data['segmentMode'] as int? ?? 0)
            .clamp(0, SegmentPlayMode.values.length - 1)],
        playlistLoop: data['playlistLoop'] as bool? ?? false,
      );
      AppLogger.info('Playlist restored: ${entries.length} entries',
          tag: 'PlaylistManager');
    } catch (e) {
      AppLogger.warning('Failed to load playlist', tag: 'PlaylistManager');
    }
  }
}
