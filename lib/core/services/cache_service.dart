import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../api/api_client.dart';
import '../logging/app_logger.dart';

/// Manages offline caching of audio segments.
///
/// Audio files are stored at:
///   <cache_dir>/audio/<segment_id>.mp3
class CacheService {
  static CacheService? _instance;
  static CacheService get instance => _instance ??= CacheService._();
  CacheService._();

  Directory? _cacheDir;

  Future<Directory> get _audioCacheDir async {
    if (_cacheDir != null) return _cacheDir!;
    final base = await getApplicationCacheDirectory();
    _cacheDir = Directory('${base.path}/audio');
    await _cacheDir!.create(recursive: true);
    return _cacheDir!;
  }

  final Map<int, Future<String>> _activeDownloads = {};

  /// Returns a local cached file path for the given segment.
  /// Downloads if not cached.
  Future<String> getAudioPath(int segmentId) async {
    if (_activeDownloads.containsKey(segmentId)) {
      return await _activeDownloads[segmentId]!;
    }

    final dir = await _audioCacheDir;
    final file = File('${dir.path}/$segmentId.mp3');

    if (await file.exists()) {
      if (await file.length() > 0) {
        AppLogger.verbose('Cache hit: segment $segmentId', tag: 'CacheService');
        return file.path;
      } else {
        AppLogger.warning('Found empty cached file for segment $segmentId, deleting and redownloading.', tag: 'CacheService');
        await file.delete();
      }
    }

    final future = _download(segmentId, file);
    _activeDownloads[segmentId] = future;
    try {
      final path = await future;
      return path;
    } finally {
      _activeDownloads.remove(segmentId);
    }
  }

  Future<String> _download(int segmentId, File finalFile) async {
    final url = '${ApiClient.baseUrl}/api/audio/$segmentId';
    AppLogger.info('Downloading audio: segment $segmentId', tag: 'CacheService');
    final tempFile = File('${finalFile.path}.tmp');
    try {
      await ApiClient.dio.download(
        url,
        tempFile.path,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            AppLogger.verbose(
                'Download progress $segmentId: ${(received / total * 100).toStringAsFixed(0)}%',
                tag: 'CacheService');
          }
        },
      );
      if (await tempFile.exists()) {
        await tempFile.rename(finalFile.path);
      }
      AppLogger.info('Downloaded segment $segmentId (${finalFile.lengthSync()} bytes)',
          tag: 'CacheService');
      return finalFile.path;
    } catch (e, st) {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      AppLogger.error('Download failed: segment $segmentId',
          tag: 'CacheService', error: e, stackTrace: st);
      rethrow;
    }
  }

  /// Pre-downloads all segments of a material in background.
  Future<void> preCacheMaterial(List<int> segmentIds) async {
    AppLogger.info('Pre-caching ${segmentIds.length} segments', tag: 'CacheService');
    for (final id in segmentIds) {
      try {
        await getAudioPath(id);
      } catch (e) {
        AppLogger.warning('Pre-cache failed for segment $id',
            tag: 'CacheService', error: e);
      }
    }
  }

  /// Returns true if the segment audio is already cached locally.
  Future<bool> isCached(int segmentId) async {
    final dir = await _audioCacheDir;
    return File('${dir.path}/$segmentId.mp3').exists();
  }

  /// Removes cached audio for a specific segment.
  Future<void> evict(int segmentId) async {
    final dir = await _audioCacheDir;
    final file = File('${dir.path}/$segmentId.mp3');
    if (await file.exists()) {
      await file.delete();
      AppLogger.debug('Evicted segment $segmentId from cache', tag: 'CacheService');
    }
  }

  /// Returns total cache size in bytes.
  Future<int> getCacheSize() async {
    final dir = await _audioCacheDir;
    int total = 0;
    await for (final entity in dir.list()) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total;
  }

  /// Clears all cached audio files.
  Future<void> clearAll() async {
    final dir = await _audioCacheDir;
    await dir.delete(recursive: true);
    await dir.create();
    AppLogger.info('Audio cache cleared', tag: 'CacheService');
  }
}
