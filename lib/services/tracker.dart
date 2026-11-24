import 'dart:math' as math;
import 'dart:ui';
import '../models/detection.dart';

class _Track {
  final int classId;
  String label;
  Rect box;
  Offset vel = Offset.zero;
  double conf;
  int hits = 1;
  int misses = 0;
  int? displayId; // atribuído só quando confirmado
  bool matchedNow = true;

  _Track(this.classId, this.label, this.box, this.conf);

  bool get confirmed => displayId != null;
  Rect predicted() => box.shift(vel * (misses + 1).toDouble());
}

/// Rastreador estilo SORT (associação gulosa por IoU + movimento constante).
/// Cada objeto confirmado recebe um ID sequencial e é contado uma única vez.
class ObjectTracker {
  final double iouMatch;
  final int minHits; // quadros seguidos para confirmar (filtra falsos positivos)
  final int maxMisses; // quadros sem ver o objeto antes de descartá-lo

  ObjectTracker({this.iouMatch = 0.25, this.minHits = 3, this.maxMisses = 8});

  final List<_Track> _tracks = [];
  int _nextId = 1;
  final Map<String, int> uniqueCounts = {};

  int get totalUnique => uniqueCounts.values.fold(0, (a, b) => a + b);

  void reset() {
    _tracks.clear();
    _nextId = 1;
    uniqueCounts.clear();
  }

  List<Detection> update(List<Detection> dets) {
    // 1) pares candidatos [score, trackIdx, detIdx]
    final pairs = <List<double>>[];
    for (int ti = 0; ti < _tracks.length; ti++) {
      final t = _tracks[ti];
      final pb = t.predicted();
      for (int di = 0; di < dets.length; di++) {
        final d = dets[di];
        if (d.classId != t.classId) continue;
        final iou = _iou(pb, d.box);
        if (iou >= iouMatch) {
          pairs.add([iou, ti.toDouble(), di.toDouble()]);
        } else {
          final dist = (pb.center - d.box.center).distance;
          final lim = math.max(t.box.width, t.box.height) * 0.6;
          if (dist < lim) {
            pairs.add([0.2 * (1 - dist / lim), ti.toDouble(), di.toDouble()]);
          }
        }
      }
    }
    pairs.sort((a, b) => b[0].compareTo(a[0]));

    final usedT = <int>{}, usedD = <int>{};
    for (final p in pairs) {
      final ti = p[1].toInt(), di = p[2].toInt();
      if (usedT.contains(ti) || usedD.contains(di)) continue;
      usedT.add(ti);
      usedD.add(di);
      final t = _tracks[ti];
      final d = dets[di];
      final v = (d.box.center - t.box.center) / (t.misses + 1).toDouble();
      t.vel = t.vel * 0.5 + v * 0.5;
      t.box = d.box;
      t.conf = d.confidence;
      t.label = d.label;
      t.hits++;
      t.misses = 0;
      t.matchedNow = true;
      if (!t.confirmed && t.hits >= minHits) {
        t.displayId = _nextId++;
        uniqueCounts[t.label] = (uniqueCounts[t.label] ?? 0) + 1;
      }
    }

    // 2) trilhas sem detecção neste quadro
    for (int ti = 0; ti < _tracks.length; ti++) {
      if (!usedT.contains(ti)) {
        _tracks[ti].misses++;
        _tracks[ti].matchedNow = false;
      }
    }
    _tracks.removeWhere(
        (t) => t.misses > (t.confirmed ? maxMisses : 2));

    // 3) detecções novas -> novas trilhas
    for (int di = 0; di < dets.length; di++) {
      if (usedD.contains(di)) continue;
      final d = dets[di];
      final t = _Track(d.classId, d.label, d.box, d.confidence);
      if (minHits <= 1) {
        t.displayId = _nextId++;
        uniqueCounts[t.label] = (uniqueCounts[t.label] ?? 0) + 1;
      }
      _tracks.add(t);
    }

    // 4) saída: só objetos confirmados vistos neste quadro
    return _tracks
        .where((t) => t.confirmed && t.matchedNow && t.misses == 0)
        .map((t) => Detection(t.box, t.classId, t.label, t.conf, t.displayId))
        .toList();
  }

  double _iou(Rect a, Rect b) {
    final i = a.intersect(b);
    if (i.width <= 0 || i.height <= 0) return 0;
    final inter = i.width * i.height;
    final union = a.width * a.height + b.width * b.height - inter;
    return union <= 0 ? 0 : inter / union;
  }
}
