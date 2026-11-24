import 'dart:convert';

class InspectionRecord {
  final int? id;
  final String imagePath;
  final DateTime createdAt;
  final String modelName;
  final Map<String, int> counts;
  final double? latitude;
  final double? longitude;
  final String? videoPath;
  final int? durationSec;

  bool get isVideo => videoPath != null;

  String get durationLabel {
    final s = durationSec ?? 0;
    return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }

  const InspectionRecord({
    this.id,
    required this.imagePath,
    required this.createdAt,
    required this.modelName,
    required this.counts,
    this.latitude,
    this.longitude,
    this.videoPath,
    this.durationSec,
  });

  String get summary => counts.isEmpty
      ? 'Nenhuma detecção'
      : (isVideo ? 'IDs únicos: ' : '') +
          counts.entries.map((e) => '${e.value}x ${e.key}').join(', ');

  String get dateLabel {
    String t(int n) => n.toString().padLeft(2, '0');
    final d = createdAt;
    return '${t(d.day)}/${t(d.month)}/${d.year} - ${t(d.hour)}:${t(d.minute)}';
  }

  String get gpsLabel => (latitude == null || longitude == null)
      ? 'GPS: indisponível'
      : 'GPS: ${latitude!.toStringAsFixed(4)}, ${longitude!.toStringAsFixed(4)}';

  Map<String, Object?> toMap() => {
        'image_path': imagePath,
        'created_at': createdAt.toIso8601String(),
        'model_name': modelName,
        'counts': jsonEncode(counts),
        'latitude': latitude,
        'longitude': longitude,
        'video_path': videoPath,
        'duration_s': durationSec,
      };

  factory InspectionRecord.fromMap(Map<String, Object?> m) => InspectionRecord(
        id: m['id'] as int?,
        imagePath: m['image_path'] as String,
        createdAt: DateTime.parse(m['created_at'] as String),
        modelName: m['model_name'] as String,
        counts: (jsonDecode(m['counts'] as String) as Map)
            .map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
        latitude: (m['latitude'] as num?)?.toDouble(),
        longitude: (m['longitude'] as num?)?.toDouble(),
        videoPath: m['video_path'] as String?,
        durationSec: m['duration_s'] as int?,
      );
}
