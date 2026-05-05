// ─── Material Models ──────────────────────────────────────────────────────────

enum MaterialStatus { pending, processing, done, failed }

enum SourceType { url_media, url_article, text, upload }

enum MediaType { video, audio, text }

enum MaterialCategory { main, temporary }

class MaterialModel {
  final int id;
  final int userId;
  final String title;
  final SourceType sourceType;
  final String? sourceUrl;
  final MediaType? mediaType;
  final double? duration;
  final String language;
  final MaterialCategory materialType;
  final MaterialStatus status;
  final String? errorMsg;
  final bool isDeleted;
  final DateTime createdAt;
  final DateTime updatedAt;

  const MaterialModel({
    required this.id,
    required this.userId,
    required this.title,
    required this.sourceType,
    this.sourceUrl,
    this.mediaType,
    this.duration,
    required this.language,
    required this.materialType,
    required this.status,
    this.errorMsg,
    required this.isDeleted,
    required this.createdAt,
    required this.updatedAt,
  });

  factory MaterialModel.fromJson(Map<String, dynamic> json) {
    return MaterialModel(
      id: json['id'] as int,
      userId: json['user_id'] as int,
      title: json['title'] as String,
      sourceType: SourceType.values.firstWhere(
          (e) => e.name == json['source_type'],
          orElse: () => SourceType.text),
      sourceUrl: json['source_url'] as String?,
      mediaType: json['media_type'] != null
          ? MediaType.values.firstWhere((e) => e.name == json['media_type'],
              orElse: () => MediaType.text)
          : null,
      duration: (json['duration'] as num?)?.toDouble(),
      language: json['language'] as String,
      materialType: MaterialCategory.values.firstWhere(
          (e) => e.name == json['material_type'],
          orElse: () => MaterialCategory.main),
      status: MaterialStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => MaterialStatus.pending),
      errorMsg: json['error_msg'] as String?,
      isDeleted: json['is_deleted'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  String get statusEmoji {
    switch (status) {
      case MaterialStatus.done:
        return '✅';
      case MaterialStatus.processing:
        return '⏳';
      case MaterialStatus.failed:
        return '❌';
      case MaterialStatus.pending:
        return '🕒';
    }
  }

  String get durationFormatted {
    if (duration == null) return '';
    final mins = (duration! / 60).floor();
    final secs = (duration! % 60).floor();
    return '${mins}m ${secs}s';
  }
}

class MaterialPage {
  final List<MaterialModel> items;
  final int total;
  final int page;
  final int size;

  const MaterialPage({
    required this.items,
    required this.total,
    required this.page,
    required this.size,
  });

  factory MaterialPage.fromJson(Map<String, dynamic> json) {
    return MaterialPage(
      items: (json['items'] as List)
          .map((e) => MaterialModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int,
      page: json['page'] as int,
      size: json['size'] as int,
    );
  }

  bool get hasMore => items.length < total;
}
