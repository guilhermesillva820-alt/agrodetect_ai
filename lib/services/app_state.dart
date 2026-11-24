import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/model_info.dart';
import 'onnx_service.dart';

class AppState extends ChangeNotifier {
  AppState._();
  static final AppState instance = AppState._();

  final OnnxService onnx = OnnxService();
  List<ModelInfo> models = [];
  String? activePath;
  bool loading = false;
  String? error;
  bool _inited = false;

  ModelInfo? get active {
    for (final m in models) {
      if (m.path == activePath) return m;
    }
    return null;
  }

  Future<void> init() async {
    if (_inited) return;
    _inited = true;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('models');
    if (raw != null) {
      models = (jsonDecode(raw) as List)
          .map((e) => ModelInfo.fromJson(e as Map<String, dynamic>))
          .where((m) => File(m.path).existsSync())
          .toList();
    }
    final act = prefs.getString('active_model');
    final m = models.where((e) => e.path == act).toList();
    if (m.isNotEmpty) await activate(m.first);
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'models', jsonEncode(models.map((m) => m.toJson()).toList()));
    if (activePath != null) await prefs.setString('active_model', activePath!);
  }

  static List<String> parseClasses(String content) {
    final d = jsonDecode(content);
    dynamic v = d;
    if (d is Map) v = d['classes'] ?? d['names'];
    if (v is List) return v.map((e) => e.toString()).toList();
    if (v is Map) {
      final keys = v.keys.toList()
        ..sort((a, b) => int.parse(a.toString()).compareTo(int.parse(b.toString())));
      return keys.map((k) => v[k].toString()).toList();
    }
    throw const FormatException('JSON de classes inválido');
  }

  Future<ModelInfo> importModel(String onnxSrc, String jsonSrc) async {
    final classes = parseClasses(await File(jsonSrc).readAsString());
    final dir = Directory(
        p.join((await getApplicationDocumentsDirectory()).path, 'models'));
    await dir.create(recursive: true);
    final dst = p.join(dir.path, '${p.basenameWithoutExtension(onnxSrc)}.onnx');
    await File(onnxSrc).copy(dst);
    final size = await File(dst).length();
    final info = ModelInfo(
      name: p.basename(dst),
      path: dst,
      classes: classes,
      sizeMb: size / 1048576,
    );
    models.removeWhere((m) => m.path == dst);
    models.add(info);
    await activate(info);
    return info;
  }

  Future<void> activate(ModelInfo info) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      await onnx.load(info.path, info.classes, info.name);
      activePath = info.path;
      await _save();
    } catch (e) {
      error = 'Falha ao carregar modelo: $e';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> remove(ModelInfo info) async {
    models.removeWhere((m) => m.path == info.path);
    try {
      await File(info.path).delete();
    } catch (_) {}
    if (activePath == info.path) {
      activePath = null;
      onnx.dispose();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('active_model');
    }
    await _save();
    notifyListeners();
  }
}
