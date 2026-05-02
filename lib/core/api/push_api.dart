import 'package:dio/dio.dart';
import '../api/api_client.dart';
import '../logging/app_logger.dart';

class PushApi {
  Dio get _dio => ApiClient.dio;

  /// Record a single segment push to Anki in backend log.
  /// The actual AnkiDroid card creation is done natively before calling this.
  Future<Map<String, dynamic>> pushSegmentToAnki(
      int segmentId, {int? ankiNoteId}) async {
    AppLogger.info('Recording push: segment=$segmentId noteId=$ankiNoteId',
        tag: 'PushApi');
    final res = await _dio.post('/api/segments/$segmentId/push', data: {
      'platform': 'anki',
      if (ankiNoteId != null) 'anki_note_id': ankiNoteId,
    });
    return res.data as Map<String, dynamic>;
  }

  /// Record a bulk material push to Anki in backend log.
  Future<List<Map<String, dynamic>>> pushMaterialToAnki(
      int materialId) async {
    AppLogger.info('Recording bulk push: material=$materialId', tag: 'PushApi');
    final res = await _dio.post('/api/materials/$materialId/push', data: {
      'platform': 'anki',
    });
    return (res.data as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> pushSegmentToTelegram(int segmentId) async {
    AppLogger.info('Pushing segment=$segmentId to Telegram', tag: 'PushApi');
    final res = await _dio.post('/api/segments/$segmentId/push', data: {
      'platform': 'telegram',
    });
    return res.data as Map<String, dynamic>;
  }
}

final pushApi = PushApi();
