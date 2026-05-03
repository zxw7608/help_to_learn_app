import 'dart:io';
import 'package:flutter_ankidroid/flutter_ankidroid.dart';
import '../logging/app_logger.dart';
import '../models/segment.dart';
import '../api/api_client.dart';
import '../api/push_api.dart';
import 'cache_service.dart';

/// Wraps flutter_ankidroid with logging and error handling.
///
/// The AnkiDroid API uses Android's ContentProvider — no network needed,
/// no AnkiConnect. The card is created directly in AnkiDroid's database.
class AnkiService {
  static AnkiService? _instance;
  static AnkiService get instance => _instance ??= AnkiService._();
  AnkiService._();

  Ankidroid? _anki;

  /// Initialize the Ankidroid isolate. Must be called before any other method.
  Future<bool> init() async {
    try {
      _anki = await Ankidroid.createAnkiIsolate();
      AppLogger.info('Ankidroid isolate created', tag: 'AnkiService');
      return true;
    } catch (e, st) {
      AppLogger.error('Failed to create Ankidroid isolate',
          tag: 'AnkiService', error: e, stackTrace: st);
      return false;
    }
  }

  /// Check if AnkiDroid is installed and API is accessible.
  Future<bool> isAvailable() async {
    try {
      if (_anki == null) await init();
      if (_anki == null) return false;
      final result = await _anki!.test();
      final ok = result.asValue != null;
      AppLogger.debug('AnkiDroid available: $ok', tag: 'AnkiService');
      return ok;
    } catch (e, st) {
      AppLogger.error('AnkiDroid availability check failed',
          tag: 'AnkiService', error: e, stackTrace: st);
      return false;
    }
  }

  /// Throws a user-friendly [Exception] if AnkiDroid is not reachable.
  /// Call this before any operation that requires AnkiDroid to be open.
  Future<void> _ensureConnected() async {
    if (_anki == null) {
      final inited = await init();
      if (!inited || _anki == null) {
        throw Exception('无法连接 AnkiDroid，请确认已安装并在后台运行');
      }
    }
    try {
      final result = await _anki!.test();
      if (result.asValue == null) {
        throw Exception('AnkiDroid 未响应，请打开 AnkiDroid 应用后再试');
      }
    } catch (e) {
      if (e is Exception && e.toString().contains('AnkiDroid')) rethrow;
      throw Exception('AnkiDroid 未响应，请打开 AnkiDroid 应用后再试');
    }
  }

  /// Request READ_WRITE permission for AnkiDroid ContentProvider.
  Future<bool> requestPermission() async {
    try {
      await Ankidroid.askForPermission();
      AppLogger.info('AnkiDroid permission requested', tag: 'AnkiService');
      return true;
    } catch (e, st) {
      AppLogger.error('AnkiDroid permission request failed',
          tag: 'AnkiService', error: e, stackTrace: st);
      return false;
    }
  }

  /// Returns list of [{'id': int, 'name': String}] deck entries.
  Future<List<Map<String, dynamic>>> getDeckList() async {
    AppLogger.debug('Fetching AnkiDroid deck list', tag: 'AnkiService');
    try {
      if (_anki == null) await init();
      final result = await _anki!.deckList();
      final decks = result.asValue?.value;
      if (decks == null) return [];
      // deckList returns Map<id, name>
      return decks.entries
          .map((e) => {'id': int.tryParse(e.key.toString()) ?? 0, 'name': e.value.toString()})
          .toList()
          .cast<Map<String, dynamic>>();
    } catch (e, st) {
      AppLogger.error('Failed to get deck list',
          tag: 'AnkiService', error: e, stackTrace: st);
      return [];
    }
  }

  /// Returns list of [{'id': int, 'name': String}] model entries.
  Future<List<Map<String, dynamic>>> getModelList() async {
    AppLogger.debug('Fetching AnkiDroid model list', tag: 'AnkiService');
    try {
      if (_anki == null) await init();
      final result = await _anki!.modelList();
      final models = result.asValue?.value;
      if (models == null) return [];
      // modelList returns Map<id, name>
      return models.entries
          .map((e) => {'id': int.tryParse(e.key.toString()) ?? 0, 'name': e.value.toString()})
          .toList()
          .cast<Map<String, dynamic>>();
    } catch (e, st) {
      AppLogger.error('Failed to get model list',
          tag: 'AnkiService', error: e, stackTrace: st);
      return [];
    }
  }

  /// Pushes a [SegmentModel] to AnkiDroid as a new note.
  ///
  /// Returns the created note ID, or null on failure.
  Future<int?> pushSegment(
    SegmentModel segment, {
    required String deckName,
    required String modelName,
  }) async {
    AppLogger.info(
      'Pushing segment ${segment.id} to Anki deck="$deckName" model="$modelName"',
      tag: 'AnkiService',
    );

    try {
      await _ensureConnected();

      // Resolve deck ID
      final deckListResult = await _anki!.deckList();
      final deckMap = deckListResult.asValue?.value ?? {};
      int? deckId;
      for (final e in deckMap.entries) {
        if (e.value.toString() == deckName) {
          deckId = int.tryParse(e.key.toString());
          break;
        }
      }
      if (deckId == null) {
        final newDeck = await _anki!.addNewDeck(deckName);
        deckId = newDeck.asValue?.value;
      }
      AppLogger.debug('Deck ID: $deckId', tag: 'AnkiService');

      // Resolve model ID
      final modelListResult = await _anki!.modelList();
      final modelMap = modelListResult.asValue?.value ?? {};
      int? modelId;
      for (final e in modelMap.entries) {
        if (e.value.toString() == modelName) {
          modelId = int.tryParse(e.key.toString());
          break;
        }
      }
      if (modelId == null) {
        AppLogger.warning('Model "$modelName" not found in AnkiDroid',
            tag: 'AnkiService');
        throw Exception('Anki model "$modelName" not found. Please create it in AnkiDroid first.');
      }
      AppLogger.debug('Model ID: $modelId', tag: 'AnkiService');

      // Build card fields
      final shareUrl = '${ApiClient.baseUrl}/share/${segment.materialId}';
      
      String front = segment.text;
      if (segment.translation != null && segment.translation!.isNotEmpty) {
        front += "<br><small style='color:#666'>${segment.translation}</small>";
      }
      front += "<br><small><a href='$shareUrl' style='color:#4a9eff'>🔗 View online</a></small>";

      String back = '[sound:${_audioFileName(segment)}]';
      try {
        final audioPath = await CacheService.instance.getAudioPath(segment.id);
        final file = File(audioPath);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          final mediaResult = await _anki!.addMedia(bytes, 'htl_seg_${segment.id}.mp3', 'audio');
          if (mediaResult.asValue?.value != null) {
            back = mediaResult.asValue!.value;
          }
        }
      } catch (e) {
        AppLogger.warning('Failed to add media to Anki', tag: 'AnkiService', error: e);
      }

      final fields = [
        front,
        back,
      ];

      // Add note
      final noteResult = await _anki!.addNote(
        modelId,
        deckId!,
        fields,
        ['help-to-learn'],
      );
      final noteId = noteResult.asValue?.value;

      AppLogger.info('Created Anki note: $noteId for segment ${segment.id}',
          tag: 'AnkiService');



      return noteId;
    } catch (e, st) {
      AppLogger.error(
        'Failed to push segment ${segment.id} to Anki',
        tag: 'AnkiService',
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  /// Pushes multiple segments as a batch.
  Future<List<AnkiPushResult>> pushSegments(
    List<SegmentModel> segments, {
    required String deckName,
    required String modelName,
    void Function(int done, int total)? onProgress,
  }) async {
    AppLogger.info(
        'Batch push: ${segments.length} segments → deck="$deckName"',
        tag: 'AnkiService');
    final results = <AnkiPushResult>[];
    for (var i = 0; i < segments.length; i++) {
      final seg = segments[i];
      try {
        final noteId =
            await pushSegment(seg, deckName: deckName, modelName: modelName);
        results.add(AnkiPushResult(segmentId: seg.id, noteId: noteId, success: true));
      } catch (e) {
        AppLogger.warning('Batch push failed for segment ${seg.id}',
            tag: 'AnkiService', error: e);
        results.add(AnkiPushResult(
            segmentId: seg.id, error: e.toString(), success: false));
      }
      onProgress?.call(i + 1, segments.length);
    }
    final ok = results.where((r) => r.success).length;
    AppLogger.info('Batch push complete: $ok/${segments.length} succeeded',
        tag: 'AnkiService');
    return results;
  }

  String _audioFileName(SegmentModel segment) =>
      'htl_seg_${segment.id}.mp3';

  void dispose() {
    _anki?.killIsolate();
    _anki = null;
  }
}

class AnkiPushResult {
  final int segmentId;
  final int? noteId;
  final bool success;
  final String? error;

  const AnkiPushResult({
    required this.segmentId,
    this.noteId,
    required this.success,
    this.error,
  });
}
