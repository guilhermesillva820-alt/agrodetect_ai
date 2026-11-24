import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VideoDialog extends StatefulWidget {
  final String path;
  const VideoDialog({super.key, required this.path});
  @override
  State<VideoDialog> createState() => _VideoDialogState();
}

class _VideoDialogState extends State<VideoDialog> {
  late final VideoPlayerController _c;

  @override
  void initState() {
    super.initState();
    _c = VideoPlayerController.file(File(widget.path))
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() {});
        _c.setLooping(true);
        _c.play();
      });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_c.value.isInitialized)
            AspectRatio(aspectRatio: _c.value.aspectRatio, child: VideoPlayer(_c))
          else
            const Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()),
          VideoProgressIndicator(_c, allowScrubbing: true),
          IconButton(
            icon: Icon(_c.value.isPlaying ? Icons.pause : Icons.play_arrow),
            onPressed: () => setState(() => _c.value.isPlaying ? _c.pause() : _c.play()),
          ),
        ],
      ),
    );
  }
}
