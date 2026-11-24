import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../models/inspection_record.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';
import '../widgets/video_dialog.dart';

class HistoryScreen extends StatefulWidget {
  final bool active;
  const HistoryScreen({super.key, required this.active});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<InspectionRecord> _all = [];
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant HistoryScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _load();
  }

  Future<void> _load() async {
    final r = await DatabaseService.all();
    if (mounted) setState(() => _all = r);
  }

  List<InspectionRecord> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _all;
    return _all
        .where((r) =>
            r.summary.toLowerCase().contains(q) ||
            r.dateLabel.contains(q) ||
            r.modelName.toLowerCase().contains(q))
        .toList();
  }

  Future<void> _exportCsv() async {
    final messenger = ScaffoldMessenger.of(context);
    if (_all.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Nada para exportar.')));
      return;
    }
    final rows = <List<dynamic>>[
      ['id', 'tipo', 'data_hora', 'duracao_s', 'modelo', 'contagem_classes', 'latitude', 'longitude', 'caminho_imagem', 'caminho_video'],
      for (final r in _all)
        [
          r.id,
          r.isVideo ? 'video' : 'foto',
          r.createdAt.toIso8601String(),
          r.durationSec ?? '',
          r.modelName,
          r.summary,
          r.latitude ?? '',
          r.longitude ?? '',
          r.imagePath,
          r.videoPath ?? '',
        ],
    ];
    final csv = const ListToCsvConverter().convert(rows);
    final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(csv)]);
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Salvar planilha CSV',
        fileName: 'agrodetect_logs.csv',
        bytes: bytes,
      );
      messenger.showSnackBar(SnackBar(
          content: Text(path == null ? 'Exportação cancelada.' : 'CSV exportado com sucesso.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Erro ao exportar: $e')));
    }
  }

  Future<void> _delete(InspectionRecord r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Excluir registro?'),
        content: Text(r.dateLabel),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Excluir')),
        ],
      ),
    );
    if (ok == true) {
      await DatabaseService.delete(r);
      _load();
    }
  }

  void _view(InspectionRecord r) {
    if (r.isVideo) {
      if (File(r.videoPath!).existsSync()) {
        showDialog(context: context, builder: (c) => VideoDialog(path: r.videoPath!));
      }
      return;
    }
    showDialog(
      context: context,
      builder: (c) => Dialog(
        child: InteractiveViewer(child: Image.file(File(r.imagePath))),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    return Scaffold(
      appBar: AppBar(title: const Text('Histórico de Inspeções')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      hintText: 'Buscar por classe/data',
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      filled: true,
                      fillColor: AppColors.forestLight,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: _exportCsv,
                  icon: const Icon(Icons.download),
                  label: const Text('Exportar CSV'),
                ),
              ],
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? const Center(
                    child: Text('Nenhum registro.', style: TextStyle(color: Colors.white60)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final r = list[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color: AppColors.forestLight,
                            borderRadius: BorderRadius.circular(14)),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              onTap: () => _view(r),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(File(r.imagePath),
                                    width: 80,
                                    height: 80,
                                    fit: BoxFit.cover,
                                    cacheWidth: 200,
                                    errorBuilder: (_, __, ___) => Container(
                                        width: 80,
                                        height: 80,
                                        color: Colors.black26,
                                        child: const Icon(Icons.broken_image))),
                              ),
                                  if (r.isVideo)
                                    const Icon(Icons.play_circle_fill,
                                        size: 34, color: Colors.white70),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      r.isVideo
                                          ? '${r.dateLabel}  •  Vídeo ${r.durationLabel}'
                                          : r.dateLabel,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold, fontSize: 15)),
                                  const SizedBox(height: 2),
                                  Text(r.gpsLabel, style: const TextStyle(fontSize: 12)),
                                  Text('Modelo: ${r.modelName}',
                                      style: const TextStyle(fontSize: 12)),
                                  const SizedBox(height: 2),
                                  Text(r.summary,
                                      style: const TextStyle(
                                          color: AppColors.leaf,
                                          fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                            IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _delete(r)),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
