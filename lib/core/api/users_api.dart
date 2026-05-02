import 'package:dio/dio.dart';
import '../api/api_client.dart';
import '../models/user.dart';
import '../logging/app_logger.dart';

class UsersApi {
  Dio get _dio => ApiClient.dio;

  Future<UserModel> getMe() async {
    final res = await _dio.get('/api/users/me');
    return UserModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<UserModel> updateMe({
    String? ankiDeckName,
    String? ankiModelName,
    String? ankiConnectUrl,
    String? telegramChatId,
    String? telegramBotToken,
    String? ttsWorkerUrl,
    String? ttsToken,
  }) async {
    final body = <String, dynamic>{};
    if (ankiDeckName != null) body['anki_deck_name'] = ankiDeckName;
    if (ankiModelName != null) body['anki_model_name'] = ankiModelName;
    if (ankiConnectUrl != null) body['anki_connect_url'] = ankiConnectUrl;
    if (telegramChatId != null) body['telegram_chat_id'] = telegramChatId;
    if (telegramBotToken != null) body['telegram_bot_token'] = telegramBotToken;
    if (ttsWorkerUrl != null) body['tts_worker_url'] = ttsWorkerUrl;
    if (ttsToken != null) body['tts_token'] = ttsToken;

    AppLogger.debug('Updating user settings: ${body.keys}', tag: 'UsersApi');
    final res = await _dio.patch('/api/users/me', data: body);
    return UserModel.fromJson(res.data as Map<String, dynamic>);
  }
}

class AuthApi {
  Dio get _dio => ApiClient.dio;

  Future<Map<String, dynamic>> login(
      {required String username, required String password}) async {
    AppLogger.info('Login attempt for user: $username', tag: 'AuthApi');
    final res = await _dio.post('/api/auth/login', data: {
      'username': username,
      'password': password,
    });
    AppLogger.info('Login successful', tag: 'AuthApi');
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> register(
      {required String username,
      required String email,
      required String password}) async {
    AppLogger.info('Register attempt for user: $username', tag: 'AuthApi');
    final res = await _dio.post('/api/auth/register', data: {
      'username': username,
      'email': email,
      'password': password,
    });
    AppLogger.info('Register successful', tag: 'AuthApi');
    return res.data as Map<String, dynamic>;
  }
}

final usersApi = UsersApi();
final authApi = AuthApi();
