import 'segment.dart';
import 'material.dart';

enum MaterialPlayMode { sequential, random, singleLoop }

enum SegmentPlayMode { sequential, random, singleLoop }

class PlaylistEntry {
  final int materialId;
  final String title;
  final String language;
  final MaterialStatus status;
  List<SegmentModel>? segments;

  PlaylistEntry({
    required this.materialId,
    required this.title,
    required this.language,
    required this.status,
    this.segments,
  });

  Map<String, dynamic> toJson() => {
        'materialId': materialId,
        'title': title,
        'language': language,
        'status': status.name,
      };

  factory PlaylistEntry.fromJson(Map<String, dynamic> json) => PlaylistEntry(
        materialId: json['materialId'] as int,
        title: json['title'] as String,
        language: json['language'] as String,
        status: MaterialStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => MaterialStatus.pending,
        ),
      );
}

class PlaylistState {
  final List<PlaylistEntry> entries;
  final int currentIndex;
  final MaterialPlayMode materialMode;
  final SegmentPlayMode segmentMode;
  final bool playlistLoop;

  const PlaylistState({
    this.entries = const [],
    this.currentIndex = -1,
    this.materialMode = MaterialPlayMode.sequential,
    this.segmentMode = SegmentPlayMode.sequential,
    this.playlistLoop = false,
  });

  PlaylistState copyWith({
    List<PlaylistEntry>? entries,
    int? currentIndex,
    MaterialPlayMode? materialMode,
    SegmentPlayMode? segmentMode,
    bool? playlistLoop,
  }) =>
      PlaylistState(
        entries: entries ?? this.entries,
        currentIndex: currentIndex ?? this.currentIndex,
        materialMode: materialMode ?? this.materialMode,
        segmentMode: segmentMode ?? this.segmentMode,
        playlistLoop: playlistLoop ?? this.playlistLoop,
      );

  bool get isEmpty => entries.isEmpty;
  bool get isNotEmpty => entries.isNotEmpty;
  bool get hasCurrent => currentIndex >= 0 && currentIndex < entries.length;
  bool get hasPrev => currentIndex > 0;
  bool get hasNext => currentIndex < entries.length - 1;

  PlaylistEntry? get current =>
      hasCurrent ? entries[currentIndex] : null;
}

extension MaterialPlayModeLabel on MaterialPlayMode {
  String get label {
    switch (this) {
      case MaterialPlayMode.sequential:
        return '素材顺序';
      case MaterialPlayMode.random:
        return '素材随机';
      case MaterialPlayMode.singleLoop:
        return '素材单循';
    }
  }

  String get shortLabel {
    switch (this) {
      case MaterialPlayMode.sequential:
        return '顺序';
      case MaterialPlayMode.random:
        return '随机';
      case MaterialPlayMode.singleLoop:
        return '单循';
    }
  }
}

extension SegmentPlayModeLabel on SegmentPlayMode {
  String get label {
    switch (this) {
      case SegmentPlayMode.sequential:
        return '片段顺序';
      case SegmentPlayMode.random:
        return '片段随机';
      case SegmentPlayMode.singleLoop:
        return '片段单循';
    }
  }

  String get shortLabel {
    switch (this) {
      case SegmentPlayMode.sequential:
        return '顺序';
      case SegmentPlayMode.random:
        return '随机';
      case SegmentPlayMode.singleLoop:
        return '单循';
    }
  }
}
