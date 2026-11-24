import 'package:flutter/material.dart';
import 'camera_screen.dart';
import 'history_screen.dart';
import 'model_manager_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _idx = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _idx,
        children: [
          CameraScreen(active: _idx == 0),
          const ModelManagerScreen(),
          HistoryScreen(active: _idx == 2),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _idx,
        onDestinationSelected: (i) => setState(() => _idx = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.photo_camera_outlined), label: 'Câmera'),
          NavigationDestination(icon: Icon(Icons.grid_view_rounded), label: 'Modelos'),
          NavigationDestination(icon: Icon(Icons.history), label: 'Histórico'),
        ],
      ),
    );
  }
}
