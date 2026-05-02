// ─── User Model ───────────────────────────────────────────────────────────────

class UserModel {
  final int id;
  final String username;
  final String email;
  final String? telegramChatId;
  final String? telegramBotToken;
  final String ankiDeckName;
  final String ankiModelName;
  final String ankiConnectUrl;
  final String ttWorkerUrl;
  final DateTime createdAt;
  final bool isActive;

  const UserModel({
    required this.id,
    required this.username,
    required this.email,
    this.telegramChatId,
    this.telegramBotToken,
    required this.ankiDeckName,
    required this.ankiModelName,
    required this.ankiConnectUrl,
    required this.ttWorkerUrl,
    required this.createdAt,
    required this.isActive,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as int,
      username: json['username'] as String,
      email: json['email'] as String,
      telegramChatId: json['telegram_chat_id'] as String?,
      telegramBotToken: json['telegram_bot_token'] as String?,
      ankiDeckName: json['anki_deck_name'] as String? ?? 'Default',
      ankiModelName: json['anki_model_name'] as String? ?? 'Basic',
      ankiConnectUrl:
          json['anki_connect_url'] as String? ?? 'http://localhost:8765',
      ttWorkerUrl: json['tts_worker_url'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
      isActive: json['is_active'] as bool,
    );
  }
}
