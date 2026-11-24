import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/detection.dart';
import '../models/inspection_record.dart';
import '../services/app_state.dart';
import '../services/database_service.dart';
import '../services/onnx_service.dart';
import '../services/tracker.dart';
import '../theme/app_theme.dart';
import '../widgets/detection_painter.dart';

class CameraScreen extends StatefulWidget {
  final bool active;
  const CameraScreen({super.key, required this.active});
  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  final _app = AppState.instance;
  final _tracker = ObjectTracker();
  CameraController? _cam;
  List<CameraDescription> _cameras = [];
  int _camIdx = 0;
  int _rotation = 90;
  bool _front = false;
  double _frameAspect = 9 / 16; // largura/altura do quadro em retrato
  bool _busy = false;
  bool _saving = false;
  String? _camError;
  String? _trackerModel;

  List<RawDet> _raw = [];
  List<Detection> _dets = []; // sem espelhamento
  double _conf = 0.50;
  double _iou = 0.45;
  double _fps = 0;
  int _lastMs = 0;
  Float32List? _lastInput;

  // gravação
  bool _recording = false;
  DateTime? _recStart;
  Timer? _recTimer;
  int _recSecs = 0;
  Position? _recPos;

  // imagem da galeria
  img.Image? _still;
  Uint8List? _stillBytes;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.active) _initCamera();
  }

  @override
  void didUpdateWidget(covariant CameraScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      _initCamera();
    } else if (!widget.active && old.active) {
      _disposeCamera();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _recording) _stopRecording();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recTimer?.cancel();
    final c = _cam;
    _cam = null;
    c?.dispose();
    super.dispose();
  }

  // ---------------- Câmera ----------------

  Future<void> _initCamera() async {
    if (_cam != null) return;
    final st = await Permission.camera.request();
    if (!st.isGranted) {
      if (mounted) setState(() => _camError = 'Permissão de câmera negada.');
      return;
    }
    try {
      if (_cameras.isEmpty) {
        _cameras = await availableCameras();
        final b = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
        _camIdx = b >= 0 ? b : 0;
      }
      if (_cameras.isEmpty) {
        if (mounted) setState(() => _camError = 'Nenhuma câmera encontrada.');
        return;
      }
      final desc = _cameras[_camIdx];
      final c = CameraController(
        desc,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await c.initialize();
      await c.startImageStream(_onFrame);
      if (!mounted || !widget.active) {
        await c.dispose();
        return;
      }
      setState(() {
        _cam = c;
        _rotation = desc.sensorOrientation;
        _front = desc.lensDirection == CameraLensDirection.front;
        _frameAspect = 1 / c.value.aspectRatio;
        _camError = null;
      });
    } catch (e) {
      if (mounted) setState(() => _camError = 'Erro na câmera: $e');
    }
  }

  Future<void> _disposeCamera() async {
    if (_recording) await _stopRecording();
    final c = _cam;
    _cam = null;
    if (c == null) return;
    if (mounted) setState(() {});
    try {
      if (c.value.isStreamingImages) await c.stopImageStream();
    } catch (_) {}
    await c.dispose();
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _recording) return;
    _camIdx = (_camIdx + 1) % _cameras.length;
    await _disposeCamera();
    _tracker.reset();
    await _initCamera();
  }

  // ---------------- Detecção + rastreamento ----------------

  Future<void> _onFrame(CameraImage ci) async {
    if (_busy || _still != null || !_app.onnx.isLoaded) return;
    _busy = true;
    try {
      if (_trackerModel != _app.activePath) {
        _trackerModel = _app.activePath;
        _tracker.reset();
      }
      final input = OnnxService.preprocessCamera(ci, _rotation);
      _lastInput = input;
      final raw = await _app.onnx.infer(input);
      if (!mounted) return;
      final tracked =
          _tracker.update(_app.onnx.postprocess(raw, _conf, _iou));
      final now = DateTime.now().millisecondsSinceEpoch;
      final inst = _lastMs == 0 ? 0 : 1000 / (now - _lastMs).clamp(1, 100000);
      _lastMs = now;
      setState(() {
        _raw = raw;
        _dets = tracked;
        _fps = _fps == 0 ? inst.toDouble() : _fps * 0.7 + inst * 0.3;
      });
    } catch (_) {
      // ignora frames com erro
    } finally {
      _busy = false;
    }
  }

  /// Só para imagem estática da galeria (sem rastreamento).
  void _applyStillFilters() {
    _dets = _app.onnx.postprocess(_raw, _conf, _iou);
  }

  List<Detection> get _shown {
    if (!_front || _still != null) return _dets;
    return _dets
        .map((d) => Detection(
            Rect.fromLTRB(1 - d.box.right, d.box.top, 1 - d.box.left, d.box.bottom),
            d.classId,
            d.label,
            d.confidence,
            d.trackId))
        .toList();
  }

  Map<String, int> get _frameCounts {
    final m = <String, int>{};
    for (final d in _dets) {
      m[d.label] = (m[d.label] ?? 0) + 1;
    }
    return m;
  }

  // ---------------- Gravação de vídeo ----------------

  Future<void> _toggleRecord() async {
    if (_saving) return;
    if (_recording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    final c = _cam;
    if (c == null || !c.value.isInitialized) return;
    if (!_app.onnx.isLoaded) {
      _toast('Ative um modelo na aba Modelos primeiro.');
      return;
    }
    if (_still != null) _closeStill();
    final locOk = await _locPermission(); // pedir ANTES (diálogo pausaria o app)
    _tracker.reset();
    _dets = [];
    try {
      if (c.value.isStreamingImages) await c.stopImageStream();
      await c.startVideoRecording(onAvailable: _onFrame);
    } catch (e) {
      _toast('Não foi possível iniciar a gravação: $e');
      try {
        if (!c.value.isStreamingImages) await c.startImageStream(_onFrame);
      } catch (_) {}
      return;
    }
    _recStart = DateTime.now();
    _recSecs = 0;
    _recPos = null;
    _recTimer?.cancel();
    _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _recSecs++);
    });
    setState(() => _recording = true);
    if (locOk) _position().then((pos) => _recPos = pos);
  }

  Future<void> _stopRecording() async {
    final c = _cam;
    if (c == null || !_recording) return;
    _recTimer?.cancel();
    setState(() {
      _recording = false;
      _saving = true;
    });
    try {
      final file = await c.stopVideoRecording();
      try {
        if (!c.value.isStreamingImages) await c.startImageStream(_onFrame);
      } catch (_) {}

      final base = (await getApplicationDocumentsDirectory()).path;
      final vdir = Directory(p.join(base, 'videos'));
      final tdir = Directory(p.join(base, 'captures'));
      await vdir.create(recursive: true);
      await tdir.create(recursive: true);
      final ts = DateTime.now().millisecondsSinceEpoch;
      final vPath = p.join(vdir.path, 'rec_$ts.mp4');
      await File(file.path).copy(vPath);
      try {
        await File(file.path).delete();
      } catch (_) {}

      // miniatura com as caixas do último quadro
      final thumb = _buildThumb();
      _drawBoxes(thumb, _dets);
      final tPath = p.join(tdir.path, 'rec_$ts.jpg');
      await File(tPath).writeAsBytes(img.encodeJpg(thumb, quality: 85));

      final secs = _recStart == null
          ? _recSecs
          : DateTime.now().difference(_recStart!).inSeconds;
      final counts = Map<String, int>.from(_tracker.uniqueCounts);
      await DatabaseService.insert(InspectionRecord(
        imagePath: tPath,
        createdAt: _recStart ?? DateTime.now(),
        modelName: _app.onnx.modelName,
        counts: counts,
        latitude: _recPos?.latitude,
        longitude: _recPos?.longitude,
        videoPath: vPath,
        durationSec: secs,
      ));
      _toast('Vídeo salvo • ${_tracker.totalUnique} objetos únicos (IDs).');
    } catch (e) {
      _toast('Erro ao salvar vídeo: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  img.Image _buildThumb() {
    final t = _lastInput;
    const s = OnnxService.inputSize;
    final w = 480;
    final h = (w / _frameAspect).round();
    if (t == null) {
      return img.Image(width: w, height: h)..clear(img.ColorRgb8(30, 30, 30));
    }
    final im = img.Image(width: s, height: s);
    for (int y = 0; y < s; y++) {
      for (int x = 0; x < s; x++) {
        final i = y * s + x;
        im.setPixelRgb(x, y, (t[i] * 255).round(), (t[s * s + i] * 255).round(),
            (t[2 * s * s + i] * 255).round());
      }
    }
    return img.copyResize(im, width: w, height: h);
  }

  // ---------------- Galeria ----------------

  Future<void> _pickImage() async {
    if (_recording) return;
    if (!_app.onnx.isLoaded) {
      _toast('Ative um modelo na aba Modelos primeiro.');
      return;
    }
    final x = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (x == null) return;
    try {
      var im = img.decodeImage(await File(x.path).readAsBytes());
      if (im == null) throw 'imagem inválida';
      im = img.bakeOrientation(im);
      if (im.width > 1280) im = img.copyResize(im, width: 1280);
      final raw = await _app.onnx.infer(OnnxService.preprocessImage(im));
      setState(() {
        _still = im;
        _stillBytes = Uint8List.fromList(img.encodeJpg(im!, quality: 90));
        _raw = raw;
        _applyStillFilters();
      });
    } catch (e) {
      _toast('Erro ao processar imagem: $e');
    }
  }

  void _closeStill() => setState(() {
        _still = null;
        _stillBytes = null;
        _raw = [];
        _dets = [];
      });

  // ---------------- Foto + registro ----------------

  Future<void> _capture() async {
    if (_saving || _recording) return;
    if (!_app.onnx.isLoaded) {
      _toast('Nenhum modelo ativo.');
      return;
    }
    setState(() => _saving = true);
    try {
      img.Image? base = _still;
      final dets = List<Detection>.from(_dets);
      final counts = Map<String, int>.from(_frameCounts);
      if (base == null) {
        final c = _cam;
        if (c == null) throw 'câmera indisponível';
        final f = await c.takePicture();
        base = img.decodeImage(await File(f.path).readAsBytes());
        try {
          await File(f.path).delete();
        } catch (_) {}
        if (base == null) throw 'falha ao decodificar foto';
        base = img.bakeOrientation(base);
      } else {
        base = base.clone();
      }
      if (base.width > 1280) base = img.copyResize(base, width: 1280);
      _drawBoxes(base, dets);

      final dir = Directory(
          p.join((await getApplicationDocumentsDirectory()).path, 'captures'));
      await dir.create(recursive: true);
      final path = p.join(dir.path, '${DateTime.now().millisecondsSinceEpoch}.jpg');
      await File(path).writeAsBytes(img.encodeJpg(base, quality: 85));

      final pos = await _position();
      await DatabaseService.insert(InspectionRecord(
        imagePath: path,
        createdAt: DateTime.now(),
        modelName: _app.onnx.modelName,
        counts: counts,
        latitude: pos?.latitude,
        longitude: pos?.longitude,
      ));
      _toast(pos == null
          ? 'Registro salvo (sem GPS).'
          : 'Registro salvo com GPS ${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}');
    } catch (e) {
      _toast('Erro ao salvar: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _drawBoxes(img.Image im, List<Detection> dets) {
    final thick = (im.width / 300).round().clamp(2, 8);
    for (final d in dets) {
      final col = detectionPalette[d.classId % detectionPalette.length];
      final c = img.ColorRgb8((col.r * 255).round(), (col.g * 255).round(), (col.b * 255).round());
      final x1 = (d.box.left * im.width).round();
      final y1 = (d.box.top * im.height).round();
      final x2 = (d.box.right * im.width).round();
      final y2 = (d.box.bottom * im.height).round();
      img.drawRect(im, x1: x1, y1: y1, x2: x2, y2: y2, color: c, thickness: thick);
      final text =
          '${d.trackId != null ? '#${d.trackId} ' : ''}${d.label} ${(d.confidence * 100).toStringAsFixed(0)}%';
      final ty = (y1 - 26) < 0 ? y1 : y1 - 26;
      img.fillRect(im,
          x1: x1, y1: ty, x2: x1 + text.length * 13 + 8, y2: ty + 26, color: c);
      img.drawString(im, text,
          font: img.arial24, x: x1 + 4, y: ty, color: img.ColorRgb8(0, 0, 0));
    }
  }

  Future<bool> _locPermission() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return false;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      return perm != LocationPermission.denied &&
          perm != LocationPermission.deniedForever;
    } catch (_) {
      return false;
    }
  }

  Future<Position?> _position() async {
    try {
      if (!await _locPermission()) return null;
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 8)),
      );
    } catch (_) {
      return null;
    }
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  // ---------------- UI ----------------

  Widget _preview() {
    if (_still != null && _stillBytes != null) {
      return Center(
        child: AspectRatio(
          aspectRatio: _still!.width / _still!.height,
          child: Stack(fit: StackFit.expand, children: [
            Image.memory(_stillBytes!, fit: BoxFit.fill, gaplessPlayback: true),
            CustomPaint(painter: DetectionPainter(_shown)),
          ]),
        ),
      );
    }
    final c = _cam;
    if (c == null || !c.value.isInitialized) {
      return Center(
        child: _camError != null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_camError!, textAlign: TextAlign.center))
            : const CircularProgressIndicator(),
      );
    }
    return Center(
      child: AspectRatio(
        aspectRatio: 1 / c.value.aspectRatio,
        child: Stack(fit: StackFit.expand, children: [
          CameraPreview(c),
          CustomPaint(painter: DetectionPainter(_shown)),
        ]),
      ),
    );
  }

  Widget _slider(String label, double v, ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label (${(v * 100).round()}%)', style: const TextStyle(fontSize: 13)),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(trackHeight: 3),
          child: Slider(
            value: v,
            min: 0.10,
            max: 0.95,
            activeColor: AppColors.leaf,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _action(IconData icon, String label, VoidCallback? onTap,
          {Color? color}) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Opacity(
          opacity: onTap == null ? 0.4 : 1,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 28, color: color),
              Text(label, style: const TextStyle(fontSize: 12)),
            ]),
          ),
        ),
      );

  String _fmt(Map<String, int> m) => m.isEmpty
      ? '—'
      : m.entries.map((e) => '${e.key}: ${e.value}').join(' | ');

  String get _recLabel =>
      '${(_recSecs ~/ 60).toString().padLeft(2, '0')}:${(_recSecs % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _app,
      builder: (context, _) {
        final live = _still == null;
        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              Positioned.fill(child: _preview()),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Column(
                    children: [
                      Container(
                        width: double.infinity,
                        color: Colors.black54,
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_recording) ...[
                              const Icon(Icons.fiber_manual_record,
                                  color: Colors.red, size: 14),
                              Text(' REC $_recLabel  •  ',
                                  style: const TextStyle(
                                      color: Colors.red, fontWeight: FontWeight.bold)),
                            ],
                            Flexible(
                              child: Text(
                                _app.loading
                                    ? 'Carregando modelo...'
                                    : _app.onnx.isLoaded
                                        ? 'Modelo Ativo: ${_app.onnx.modelName} | FPS: ${_fps.toStringAsFixed(0)}'
                                        : 'Nenhum modelo ativo — importe na aba Modelos',
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.fromLTRB(18, 8, 8, 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.45),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Column(mainAxisSize: MainAxisSize.min, children: [
                              Text(live ? 'Contagem (IDs únicos)' : 'Contagem',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold, fontSize: 14)),
                              Text(
                                  live
                                      ? '${_fmt(_tracker.uniqueCounts)}'
                                      : _fmt(_frameCounts),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold, fontSize: 15)),
                              if (live)
                                Text('No quadro: ${_fmt(_frameCounts)}',
                                    style: const TextStyle(
                                        fontSize: 11, color: Colors.white70)),
                            ]),
                            if (live)
                              IconButton(
                                tooltip: 'Zerar contagem',
                                icon: const Icon(Icons.restart_alt),
                                onPressed: _recording
                                    ? null
                                    : () => setState(() {
                                          _tracker.reset();
                                          _dets = [];
                                        }),
                              ),
                          ],
                        ),
                      ),
                      if (!live)
                        Align(
                          alignment: Alignment.centerRight,
                          child: IconButton.filledTonal(
                            onPressed: _closeStill,
                            icon: const Icon(Icons.close),
                            tooltip: 'Voltar à câmera',
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  decoration: BoxDecoration(
                    color: AppColors.forest.withOpacity(0.85),
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _slider('Confiança', _conf, (v) => setState(() {
                            _conf = v;
                            if (_still != null) _applyStillFilters();
                          })),
                      _slider('IoU (NMS)', _iou, (v) => setState(() {
                            _iou = v;
                            if (_still != null) _applyStillFilters();
                          })),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _action(Icons.photo_library_outlined, 'Galeria',
                              _recording ? null : _pickImage),
                          SizedBox(
                            width: 76,
                            height: 76,
                            child: FilledButton(
                              onPressed: (_saving || _recording) ? null : _capture,
                              style: FilledButton.styleFrom(
                                  shape: const CircleBorder(),
                                  padding: EdgeInsets.zero,
                                  backgroundColor: AppColors.leaf),
                              child: _saving
                                  ? const CircularProgressIndicator(color: Colors.white)
                                  : const Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.photo_camera, size: 28),
                                        Text('CAPTURAR',
                                            style: TextStyle(
                                                fontSize: 9, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                            ),
                          ),
                          _action(
                            _recording ? Icons.stop_circle : Icons.videocam,
                            _recording ? 'Parar' : 'Gravar',
                            (_saving || !live || _cam == null) ? null : _toggleRecord,
                            color: Colors.redAccent,
                          ),
                          _action(Icons.cameraswitch_outlined, 'Trocar',
                              _recording ? null : _switchCamera),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
