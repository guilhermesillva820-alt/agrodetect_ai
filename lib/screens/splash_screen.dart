import 'dart:async';
import 'package:flutter/material.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
import 'home_shell.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    AppState.instance.init();
    Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeShell()));
    });
  }

  Widget _tag(String text, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        color: c,
        child: Text(text,
            style: const TextStyle(
                color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold)),
      );

  Widget _box(IconData icon, String label, Color c, double size) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _tag(label, c),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(border: Border.all(color: c, width: 2.5)),
            child: Icon(icon, size: size, color: AppColors.leaf),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.forest, Color(0xFF0B3B2E)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 2),
              const Icon(Icons.center_focus_strong,
                  size: 64, color: AppColors.leaf),
              const SizedBox(height: 12),
              RichText(
                text: const TextSpan(
                  style: TextStyle(fontSize: 38, fontWeight: FontWeight.w900),
                  children: [
                    TextSpan(text: 'AGRO', style: TextStyle(color: Colors.white)),
                    TextSpan(
                        text: 'DETECT AI', style: TextStyle(color: AppColors.leaf)),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _box(Icons.bug_report, 'Lagarta (92%)', AppColors.orange, 40),
                  const SizedBox(width: 12),
                  _box(Icons.eco, 'Saudável (99%)', AppColors.leaf, 72),
                  const SizedBox(width: 12),
                  _box(Icons.spa, 'Ferrugem (87%)', AppColors.amber, 40),
                ],
              ),
              const Spacer(),
              const Text('Detecção Inteligente\npara o Campo',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 26, fontWeight: FontWeight.bold, height: 1.2)),
              const Spacer(flex: 2),
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Text('Desenvolvedor: Guilherme Silva Soares',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.white60)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
