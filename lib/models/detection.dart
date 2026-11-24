import 'dart:ui';

/// Candidato bruto (coordenadas normalizadas 0..1, centro/largura/altura).
class RawDet {
  final double cx, cy, w, h, score;
  final int classId;
  const RawDet(this.cx, this.cy, this.w, this.h, this.score, this.classId);
}

/// Detecção final (retângulo proporcional 0..1 ao quadro).
class Detection {
  final Rect box;
  final int classId;
  final String label;
  final double confidence;
  final int? trackId; // ID único do objeto (rastreamento)
  const Detection(this.box, this.classId, this.label, this.confidence,
      [this.trackId]);
}
