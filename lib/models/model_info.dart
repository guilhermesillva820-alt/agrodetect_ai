class ModelInfo {
  final String name;
  final String path;
  final List<String> classes;
  final double sizeMb;
  const ModelInfo({
    required this.name,
    required this.path,
    required this.classes,
    required this.sizeMb,
  });

  Map<String, dynamic> toJson() =>
      {'name': name, 'path': path, 'classes': classes, 'sizeMb': sizeMb};

  factory ModelInfo.fromJson(Map<String, dynamic> j) => ModelInfo(
        name: j['name'] as String,
        path: j['path'] as String,
        classes: (j['classes'] as List).map((e) => e.toString()).toList(),
        sizeMb: (j['sizeMb'] as num).toDouble(),
      );
}
