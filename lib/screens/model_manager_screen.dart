import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';

class ModelManagerScreen extends StatelessWidget {
  const ModelManagerScreen({super.key});

  Future<void> _import(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final onnx = await FilePicker.platform.pickFiles(
        dialogTitle: 'Selecione o modelo .onnx',
        type: FileType.custom,
        allowedExtensions: ['onnx']);
    final onnxPath = onnx?.files.single.path;
    if (onnxPath == null) return;
    final json = await FilePicker.platform.pickFiles(
        dialogTitle: 'Selecione o .json de classes',
        type: FileType.custom,
        allowedExtensions: ['json']);
    final jsonPath = json?.files.single.path;
    if (jsonPath == null) return;
    try {
      final info = await AppState.instance.importModel(onnxPath, jsonPath);
      messenger.showSnackBar(
          SnackBar(content: Text('Modelo ${info.name} importado e ativado.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Erro ao importar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) {
        final s = AppState.instance;
        return Scaffold(
          appBar: AppBar(title: const Text('Gerenciador de Modelos')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              FilledButton.tonalIcon(
                onPressed: s.loading ? null : () => _import(context),
                icon: const Icon(Icons.add),
                label: const Text('Importar Novo Modelo (.onnx + .json)'),
              ),
              if (s.loading)
                const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator()),
              if (s.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(s.error!,
                      style: const TextStyle(color: Colors.redAccent)),
                ),
              const SizedBox(height: 16),
              if (s.models.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'Nenhum modelo importado.\nImporte um YOLO .onnx e o .json com as classes.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white60),
                  ),
                ),
              for (final m in s.models)
                Builder(builder: (context) {
                  final isActive = m.path == s.activePath;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: AppColors.forestLight,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: isActive ? AppColors.leaf : Colors.transparent,
                          width: 2),
                    ),
                    child: ListTile(
                      onTap: isActive || s.loading ? null : () => s.activate(m),
                      leading: Icon(
                          isActive ? Icons.check_circle : Icons.radio_button_unchecked,
                          color: isActive ? AppColors.leaf : Colors.white54),
                      title: Text(m.name,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        '${isActive ? 'EM USO • ' : 'Toque para selecionar • '}'
                        '${m.sizeMb.toStringAsFixed(1)} MB\n'
                        'Entrada: 640x640\nClasses: ${m.classes.join(', ')}',
                      ),
                      isThreeLine: true,
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (c) => AlertDialog(
                              title: const Text('Remover modelo?'),
                              content: Text(m.name),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(c, false),
                                    child: const Text('Cancelar')),
                                FilledButton(
                                    onPressed: () => Navigator.pop(c, true),
                                    child: const Text('Remover')),
                              ],
                            ),
                          );
                          if (ok == true) await s.remove(m);
                        },
                      ),
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }
}
