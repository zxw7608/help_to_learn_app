import 'package:dio/dio.dart';
import '../api/api_client.dart';
import '../models/analysis_record.dart';
import '../logging/app_logger.dart';

class AnalysisApi {
  Dio get _dio => ApiClient.dio;

  Future<AnalysisRecord> save(int segmentId,
      {required String selectedPhrase, required String analysis}) async {
    AppLogger.debug('Saving analysis for segment $segmentId', tag: 'AnalysisApi');
    final res = await _dio.post('/api/segments/$segmentId/analysis', data: {
      'selected_phrase': selectedPhrase,
      'analysis': analysis,
    });
    return AnalysisRecord.fromJson(res.data as Map<String, dynamic>);
  }

  Future<List<AnalysisRecord>> forSegment(int segmentId) async {
    AppLogger.debug('Fetching analysis for segment $segmentId',
        tag: 'AnalysisApi');
    final res = await _dio.get('/api/segments/$segmentId/analysis');
    return (res.data as List)
        .map((e) => AnalysisRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<AnalysisRecord>> list({int page = 1, int size = 20}) async {
    AppLogger.debug('Fetching analysis records page=$page', tag: 'AnalysisApi');
    final res = await _dio.get('/api/analysis-records',
        queryParameters: {'page': page, 'size': size});
    return (res.data as List)
        .map((e) => AnalysisRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

final analysisApi = AnalysisApi();
