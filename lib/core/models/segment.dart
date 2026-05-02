// ─── Segment Model ────────────────────────────────────────────────────────────

enum AudioSourceType { tts, original }

class SegmentModel {
  final int id;
  final int materialId;
  final int userId;
  final int index;
  final double? startTime;
  final double? endTime;
  final double? duration;
  final String text;
  final String? translation;
  final AudioSourceType audioSourceType;
  final String audioFilePath;
  final DateTime createdAt;

  const SegmentModel({
    required this.id,
    required this.materialId,
    required this.userId,
    required this.index,
    this.startTime,
    this.endTime,
    this.duration,
    required this.text,
    this.translation,
    required this.audioSourceType,
    required this.audioFilePath,
    required this.createdAt,
  });

  factory SegmentModel.fromJson(Map<String, dynamic> json) {
    return SegmentModel(
      id: json['id'] as int,
      materialId: json['material_id'] as int,
      userId: json['user_id'] as int,
      index: json['index'] as int,
      startTime: (json['start_time'] as num?)?.toDouble(),
      endTime: (json['end_time'] as num?)?.toDouble(),
      duration: (json['duration'] as num?)?.toDouble(),
      text: json['text'] as String,
      translation: json['translation'] as String?,
      audioSourceType: AudioSourceType.values.firstWhere(
          (e) => e.name == json['audio_source_type'],
          orElse: () => AudioSourceType.tts),
      audioFilePath: json['audio_file_path'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  /// Returns the full URL for the audio stream.
  String audioUrl(String baseUrl) => '$baseUrl/api/audio/$id';
}
