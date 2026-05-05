import 'package:dio/dio.dart';
import '../api/api_client.dart';
import '../models/material.dart';
import '../logging/app_logger.dart';

class MaterialsApi {
  Dio get _dio => ApiClient.dio;

  Future<MaterialPage> list({
    int page = 1,
    int size = 20,
    String? materialType,
  }) async {
    AppLogger.debug('Fetching materials page=$page type=$materialType', tag: 'MaterialsApi');
    final params = <String, dynamic>{
      'page': page,
      'size': size,
    };
    if (materialType != null) params['material_type'] = materialType;
    final res = await _dio.get('/api/materials', queryParameters: params);
    return MaterialPage.fromJson(res.data as Map<String, dynamic>);
  }

  Future<MaterialModel> get(int id) async {
    final res = await _dio.get('/api/materials/$id');
    return MaterialModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<List<Map<String, dynamic>>> getSegmentsRaw(int materialId) async {
    final res = await _dio.get('/api/materials/$materialId/segments');
    return (res.data as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> importUrlMedia({
    required String url,
    String? title,
    String language = 'en',
    String materialType = 'main',
  }) async {
    AppLogger.info('Importing URL media: $url', tag: 'MaterialsApi');
    final res = await _dio.post('/api/materials/url-media', data: {
      'url': url,
      if (title != null) 'title': title,
      'language': language,
      'material_type': materialType,
    });
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> importUrlArticle({
    required String url,
    String? title,
    String language = 'en',
    String materialType = 'main',
  }) async {
    AppLogger.info('Importing URL article: $url', tag: 'MaterialsApi');
    final res = await _dio.post('/api/materials/url-article', data: {
      'url': url,
      if (title != null) 'title': title,
      'language': language,
      'material_type': materialType,
    });
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> importText({
    required String text,
    required String title,
    String language = 'en',
    String materialType = 'main',
  }) async {
    AppLogger.info('Importing text: "${title.substring(0, title.length.clamp(0, 30))}..."',
        tag: 'MaterialsApi');
    final res = await _dio.post('/api/materials/text', data: {
      'text': text,
      'title': title,
      'language': language,
      'material_type': materialType,
    });
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> importTextSnippet({
    required String text,
    String? title,
    String language = 'en',
  }) async {
    AppLogger.info('Importing text snippet', tag: 'MaterialsApi');
    final res = await _dio.post('/api/materials/text-snippet', data: {
      'text': text,
      if (title != null) 'title': title,
      'language': language,
    });
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> uploadFile({
    required String filePath,
    required String fileName,
    required String title,
    String language = 'en',
    String materialType = 'main',
  }) async {
    AppLogger.info('Uploading file: $fileName', tag: 'MaterialsApi');
    final formData = FormData.fromMap({
      'title': title,
      'language': language,
      'material_type': materialType,
      'file': await MultipartFile.fromFile(filePath, filename: fileName),
    });
    final res = await _dio.post('/api/materials/upload', data: formData);
    return res.data as Map<String, dynamic>;
  }

  Future<void> deleteMaterial(int id) async {
    AppLogger.info('Deleting material id=$id', tag: 'MaterialsApi');
    await _dio.delete('/api/materials/$id');
  }

  Future<void> deleteMaterialStorage(int id) async {
    AppLogger.info('Deleting material storage id=$id', tag: 'MaterialsApi');
    await _dio.delete('/api/materials/$id/storage');
  }

  Future<Map<String, dynamic>> reExecute(int materialId) async {
    AppLogger.info('Re-executing material id=$materialId', tag: 'MaterialsApi');
    final res = await _dio.post('/api/materials/$materialId/re-execute');
    return res.data as Map<String, dynamic>;
  }
}

final materialsApi = MaterialsApi();
