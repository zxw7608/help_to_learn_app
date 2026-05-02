import 'package:dio/dio.dart';
import '../logging/app_logger.dart';

/// Dio interceptor that logs every HTTP request and response.
class LogInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    AppLogger.debug(
      '→ ${options.method} ${options.path}',
      tag: 'HTTP',
      data: options.data != null ? 'body: ${options.data}' : null,
    );
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final duration = _elapsed(response.requestOptions);
    final emoji = response.statusCode != null && response.statusCode! >= 400
        ? '❌'
        : '✅';
    AppLogger.info(
      '$emoji ← ${response.statusCode} ${response.requestOptions.method} '
      '${response.requestOptions.path} (${duration}ms)',
      tag: 'HTTP',
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    AppLogger.error(
      '❌ HTTP Error ${err.response?.statusCode ?? "N/A"}: '
      '${err.requestOptions.method} ${err.requestOptions.path}\n'
      '${err.message}',
      tag: 'HTTP',
      error: err,
      stackTrace: err.stackTrace,
    );
    handler.next(err);
  }

  int _elapsed(RequestOptions options) {
    final extra = options.extra['__startTime__'];
    if (extra is DateTime) {
      return DateTime.now().difference(extra).inMilliseconds;
    }
    return -1;
  }
}

/// Interceptor that stamps request start time for duration calculation.
class TimingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra['__startTime__'] = DateTime.now();
    handler.next(options);
  }
}
