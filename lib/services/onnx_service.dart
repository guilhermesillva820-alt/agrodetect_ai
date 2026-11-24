import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';
import '../models/detection.dart';

/// Gerencia o ciclo de vida da OrtSession + pré/pós-processamento YOLO.
class OnnxService {
  static const int inputSize = 640;
  static const double minScore = 0.10;

  OrtSession? _session;
  OrtSessionOptions? _opts;
  String? _inputName;
  List<String> classes = [];
  String modelName = '';

  bool get isLoaded => _session != null;

  Future<void> load(String path, List<String> classNames, String name) async {
    dispose();
    OrtEnv.instance.init();
    _opts = OrtSessionOptions()
      ..setInterOpNumThreads(1)
      ..setIntraOpNumThreads(4);
    _session = OrtSession.fromFile(File(path), _opts!);
    _inputName = _session!.inputNames.first;
    classes = classNames;
    modelName = name;
  }

  void dispose() {
    _session?.release();
    _opts?.release();
    _session = null;
    _opts = null;
  }

  // ---------------- PRÉ-PROCESSAMENTO ----------------

  /// Frame da câmera (YUV420 / BGRA) -> tensor CHW [3,640,640] normalizado 0..1,
  /// já rotacionado conforme a orientação do sensor.
  static Float32List preprocessCamera(CameraImage ci, int rotation) {
    const s = inputSize;
    final w = ci.width, h = ci.height;
    final sideways = rotation == 90 || rotation == 270;
    final rw = sideways ? h : w;
    final rh = sideways ? w : h;
    final out = Float32List(3 * s * s);
    const plane = s * s;
    final bgra = ci.format.group == ImageFormatGroup.bgra8888;
    final p0 = ci.planes[0];
    final p1 = ci.planes.length > 1 ? ci.planes[1] : null;
    final p2 = ci.planes.length > 2 ? ci.planes[2] : null;

    for (int oy = 0; oy < s; oy++) {
      final ry = math.min(rh - 1, (oy * rh) ~/ s);
      for (int ox = 0; ox < s; ox++) {
        final rx = math.min(rw - 1, (ox * rw) ~/ s);
        int sx, sy;
        switch (rotation) {
          case 90:
            sx = ry;
            sy = h - 1 - rx;
            break;
          case 180:
            sx = w - 1 - rx;
            sy = h - 1 - ry;
            break;
          case 270:
            sx = w - 1 - ry;
            sy = rx;
            break;
          default:
            sx = rx;
            sy = ry;
        }
        double r, g, b;
        if (bgra || p1 == null || p2 == null) {
          final idx = sy * p0.bytesPerRow + sx * 4;
          b = p0.bytes[idx].toDouble();
          g = p0.bytes[idx + 1].toDouble();
          r = p0.bytes[idx + 2].toDouble();
        } else {
          final y = p0.bytes[sy * p0.bytesPerRow + sx].toDouble();
          final u = p1.bytes[(sy >> 1) * p1.bytesPerRow +
                  (sx >> 1) * (p1.bytesPerPixel ?? 1)] -
              128;
          final v = p2.bytes[(sy >> 1) * p2.bytesPerRow +
                  (sx >> 1) * (p2.bytesPerPixel ?? 1)] -
              128;
          r = y + 1.402 * v;
          g = y - 0.344136 * u - 0.714136 * v;
          b = y + 1.772 * u;
        }
        final i = oy * s + ox;
        out[i] = r.clamp(0.0, 255.0) / 255.0;
        out[plane + i] = g.clamp(0.0, 255.0) / 255.0;
        out[2 * plane + i] = b.clamp(0.0, 255.0) / 255.0;
      }
    }
    return out;
  }

  /// Imagem estática -> tensor CHW [3,640,640] normalizado 0..1.
  static Float32List preprocessImage(img.Image src) {
    const s = inputSize;
    final r = img.copyResize(src,
        width: s, height: s, interpolation: img.Interpolation.linear);
    final out = Float32List(3 * s * s);
    const plane = s * s;
    for (int y = 0; y < s; y++) {
      for (int x = 0; x < s; x++) {
        final px = r.getPixel(x, y);
        final i = y * s + x;
        out[i] = px.r / 255.0;
        out[plane + i] = px.g / 255.0;
        out[2 * plane + i] = px.b / 255.0;
      }
    }
    return out;
  }

  // ---------------- INFERÊNCIA ----------------

  Future<List<RawDet>> infer(Float32List input) async {
    final s = _session;
    if (s == null) return [];
    final tensor = OrtValueTensor.createTensorWithDataList(
        input, [1, 3, inputSize, inputSize]);
    final runOpts = OrtRunOptions();
    List<OrtValue?>? outputs;
    try {
      outputs = await s.runAsync(runOpts, {_inputName!: tensor});
      if (outputs == null || outputs.isEmpty) return [];
      return _decode(outputs.first?.value);
    } finally {
      tensor.release();
      runOpts.release();
      outputs?.forEach((o) => o?.release());
    }
  }

  /// Decodifica [1, 4+nc, 8400] (ou transposto [1, 8400, 4+nc]).
  List<RawDet> _decode(dynamic value) {
    if (value is! List || value.isEmpty) return [];
    final rows = value[0];
    if (rows is! List || rows.isEmpty) return [];
    final a = rows.length;
    final b = (rows[0] as List).length;
    final channelFirst = a < b;
    final attrs = channelFirst ? a : b;
    final n = channelFirst ? b : a;
    final nc = attrs - 4;
    if (nc <= 0) return [];

    double v(int attr, int i) =>
        ((channelFirst ? rows[attr][i] : rows[i][attr]) as num).toDouble();

    final tmp = <List<double>>[];
    double maxCoord = 0;
    for (int i = 0; i < n; i++) {
      double best = -1;
      int bestC = 0;
      for (int c = 0; c < nc; c++) {
        final sc = v(4 + c, i);
        if (sc > best) {
          best = sc;
          bestC = c;
        }
      }
      if (best < minScore) continue;
      final cx = v(0, i), cy = v(1, i), w = v(2, i), h = v(3, i);
      maxCoord = math.max(maxCoord, math.max(cx, cy));
      tmp.add([cx, cy, w, h, best, bestC.toDouble()]);
    }
    final k = maxCoord > 2 ? 1.0 / inputSize : 1.0; // pixels -> normalizado
    tmp.sort((x, y) => y[4].compareTo(x[4]));
    return tmp
        .take(500)
        .map((d) => RawDet(d[0] * k, d[1] * k, d[2] * k, d[3] * k, d[4], d[5].toInt()))
        .toList();
  }

  // ---------------- PÓS-PROCESSAMENTO (confiança + NMS) ----------------

  List<Detection> postprocess(
      List<RawDet> raw, double confThreshold, double iouThreshold) {
    final cand = raw.where((r) => r.score >= confThreshold).toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    final keep = <RawDet>[];
    for (final c in cand) {
      bool ok = true;
      for (final k in keep) {
        if (k.classId == c.classId && _iou(k, c) > iouThreshold) {
          ok = false;
          break;
        }
      }
      if (ok) keep.add(c);
    }
    return keep.map((r) {
      final rect = Rect.fromLTRB(
        (r.cx - r.w / 2).clamp(0.0, 1.0),
        (r.cy - r.h / 2).clamp(0.0, 1.0),
        (r.cx + r.w / 2).clamp(0.0, 1.0),
        (r.cy + r.h / 2).clamp(0.0, 1.0),
      );
      final label =
          r.classId < classes.length ? classes[r.classId] : 'classe${r.classId}';
      return Detection(rect, r.classId, label, r.score);
    }).toList();
  }

  double _iou(RawDet a, RawDet b) {
    final ax1 = a.cx - a.w / 2, ay1 = a.cy - a.h / 2;
    final ax2 = a.cx + a.w / 2, ay2 = a.cy + a.h / 2;
    final bx1 = b.cx - b.w / 2, by1 = b.cy - b.h / 2;
    final bx2 = b.cx + b.w / 2, by2 = b.cy + b.h / 2;
    final iw = math.max(0.0, math.min(ax2, bx2) - math.max(ax1, bx1));
    final ih = math.max(0.0, math.min(ay2, by2) - math.max(ay1, by1));
    final inter = iw * ih;
    final union = a.w * a.h + b.w * b.h - inter;
    return union <= 0 ? 0 : inter / union;
  }
}
