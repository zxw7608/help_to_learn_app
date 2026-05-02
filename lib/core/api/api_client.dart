import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../logging/app_logger.dart';
import '../logging/log_interceptor.dart' as app_log;

const _kBaseUrlKey = 'server_base_url';
const _kDefaultBaseUrl = 'https://study.100on.de';
const _kAccessTokenKey = 'access_token';
const _kRefreshTokenKey = 'refresh_token';

final _secureStorage = const FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);

/// Provides the configured Dio instance with auth + logging interceptors.
final apiClientProvider = Provider<Dio>((ref) {
  final dio = Dio();
  // Will be configured on first use via [ApiClient.initialize]
  return dio;
});

class ApiClient {
  static late Dio _dio;
  static String _baseUrl = _kDefaultBaseUrl;

  static Future<void> initialize() async {
    final savedUrl = await _secureStorage.read(key: _kBaseUrlKey);
    _baseUrl = savedUrl ?? _kDefaultBaseUrl;
    _setupDio();
    AppLogger.info('ApiClient initialized, baseUrl: $_baseUrl', tag: 'ApiClient');
  }

  static Future<void> setBaseUrl(String url) async {
    _baseUrl = url.trimRight().replaceAll(RegExp(r'/$'), '');
    await _secureStorage.write(key: _kBaseUrlKey, value: _baseUrl);
    _setupDio();
    AppLogger.info('Base URL updated: $_baseUrl', tag: 'ApiClient');
  }

  static String get baseUrl => _baseUrl;

  static Dio get dio => _dio;

  static void _setupDio() {
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ));

    _dio.interceptors.addAll([
      app_log.TimingInterceptor(),
      app_log.LogInterceptor(),
      _AuthInterceptor(_dio),
    ]);
  }
}

// ─── Auth Token Interceptor ───────────────────────────────────────────────────

class _AuthInterceptor extends Interceptor {
  final Dio _dio;
  bool _isRefreshing = false;

  _AuthInterceptor(this._dio);

  @override
  void onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    // Skip auth for auth endpoints
    if (options.path.contains('/api/auth/')) {
      return handler.next(options);
    }
    final token = await _secureStorage.read(key: _kAccessTokenKey);
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401 && !_isRefreshing) {
      _isRefreshing = true;
      AppLogger.info('Token expired, attempting refresh...', tag: 'AuthInterceptor');
      try {
        final refreshToken = await _secureStorage.read(key: _kRefreshTokenKey);
        if (refreshToken == null) throw Exception('No refresh token');

        final response = await _dio.post(
          '/api/auth/refresh',
          data: {'refresh_token': refreshToken},
          options: Options(headers: {'Authorization': null}),
        );

        final newToken = response.data['access_token'] as String;
        await _secureStorage.write(key: _kAccessTokenKey, value: newToken);
        AppLogger.info('Token refreshed successfully', tag: 'AuthInterceptor');

        // Retry original request with new token
        final opts = err.requestOptions;
        opts.headers['Authorization'] = 'Bearer $newToken';
        final retryResponse = await _dio.fetch(opts);
        _isRefreshing = false;
        return handler.resolve(retryResponse);
      } catch (e) {
        _isRefreshing = false;
        AppLogger.warning('Token refresh failed, user needs to login again',
            tag: 'AuthInterceptor', error: e);
        // Clear stored tokens
        await _secureStorage.delete(key: _kAccessTokenKey);
        await _secureStorage.delete(key: _kRefreshTokenKey);
      }
    }
    handler.next(err);
  }
}

// ─── Token Helpers ────────────────────────────────────────────────────────────

class TokenStorage {
  static bool _hasTokenSync = false;

  /// Must be called before [runApp] to cache token status for sync redirect.
  static Future<void> initSync() async {
    _hasTokenSync = await hasToken();
  }

  /// Synchronous check — use only after [initSync] was called.
  static bool get hasTokenSync => _hasTokenSync;

  static Future<void> saveTokens(
      {required String accessToken, required String refreshToken}) async {
    _hasTokenSync = true;
    await _secureStorage.write(key: _kAccessTokenKey, value: accessToken);
    await _secureStorage.write(key: _kRefreshTokenKey, value: refreshToken);
    AppLogger.debug('Tokens saved', tag: 'TokenStorage');
  }

  static Future<void> clear() async {
    _hasTokenSync = false;
    await _secureStorage.delete(key: _kAccessTokenKey);
    await _secureStorage.delete(key: _kRefreshTokenKey);
    AppLogger.info('Tokens cleared (logout)', tag: 'TokenStorage');
  }

  static Future<bool> hasToken() async {
    final token = await _secureStorage.read(key: _kAccessTokenKey);
    return token != null;
  }
}
