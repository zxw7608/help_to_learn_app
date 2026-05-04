// ─── Analysis Record Model ─────────────────────────────────────────────────────

class AnalysisRecord {
  final int id;
  final int segmentId;
  final int userId;
  final String selectedPhrase;
  final String analysis;
  final DateTime createdAt;

  const AnalysisRecord({
    required this.id,
    required this.segmentId,
    required this.userId,
    required this.selectedPhrase,
    required this.analysis,
    required this.createdAt,
  });

  factory AnalysisRecord.fromJson(Map<String, dynamic> json) {
    return AnalysisRecord(
      id: json['id'] as int,
      segmentId: json['segment_id'] as int,
      userId: json['user_id'] as int,
      selectedPhrase: json['selected_phrase'] as String,
      analysis: json['analysis'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
