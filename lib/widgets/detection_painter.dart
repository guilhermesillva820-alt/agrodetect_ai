import 'package:flutter/material.dart';
import '../models/detection.dart';
import '../theme/app_theme.dart';

const detectionPalette = <Color>[
  AppColors.orange,
  AppColors.amber,
  Color(0xFFFF5722),
  Color(0xFFCDDC39),
  Color(0xFFFFB74D),
];

class DetectionPainter extends CustomPainter {
  final List<Detection> detections;
  DetectionPainter(this.detections);

  @override
  void paint(Canvas canvas, Size size) {
    for (final d in detections) {
      final color = detectionPalette[d.classId % detectionPalette.length];
      final r = Rect.fromLTRB(d.box.left * size.width, d.box.top * size.height,
          d.box.right * size.width, d.box.bottom * size.height);
      canvas.drawRect(
        r,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: ' ${d.trackId != null ? '#${d.trackId} ' : ''}${d.label} ${(d.confidence * 100).toStringAsFixed(0)}% ',
          style: const TextStyle(
              color: Colors.black, fontSize: 13, fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final top = (r.top - tp.height) < 0 ? r.top : r.top - tp.height;
      final left = r.left.clamp(0.0, (size.width - tp.width).clamp(0.0, size.width));
      canvas.drawRect(Rect.fromLTWH(left, top, tp.width, tp.height),
          Paint()..color = color);
      tp.paint(canvas, Offset(left, top));
    }
  }

  @override
  bool shouldRepaint(covariant DetectionPainter old) => old.detections != detections;
}
