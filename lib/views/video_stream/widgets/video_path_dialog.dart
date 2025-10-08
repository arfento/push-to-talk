import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VideoPathDialog extends StatefulWidget {
  final String videoPath;

  const VideoPathDialog({Key? key, required this.videoPath}) : super(key: key);

  @override
  State<VideoPathDialog> createState() => _VideoPathDialogState();
}

class _VideoPathDialogState extends State<VideoPathDialog> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initializeVideoPlayer();
  }

  Future<void> _initializeVideoPlayer() async {
    try {
      // Check if file exists
      File videoFile = File(widget.videoPath);
      bool fileExists = await videoFile.exists();

      if (!fileExists) {
        setState(() {
          _hasError = true;
        });
        return;
      }

      // Get file size for debugging
      int fileSize = await videoFile.length();
      print('🎬 Video file size: $fileSize bytes');

      _controller = VideoPlayerController.file(videoFile)
        ..initialize().then((_) {
          if (mounted) {
            setState(() => _isInitialized = true);
          }
          _controller.play();
          _controller.setLooping(true);
        })
        ..addListener(() {
          if (mounted) setState(() {});
        });
    } catch (e) {
      print('❌ Error initializing video player: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Received Video',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Video Player or Error/Placeholder
            if (_hasError)
              _buildErrorWidget()
            else if (!_isInitialized)
              _buildLoadingWidget()
            else
              Expanded(
                child: SingleChildScrollView(child: _buildVideoPlayer()),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoPlayer() {
    return Column(
      children: [
        // Video
        AspectRatio(
          aspectRatio: _controller.value.aspectRatio,
          child: VideoPlayer(_controller),
        ),
        const SizedBox(height: 16),

        // Controls
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: Icon(Icons.replay_10, color: Colors.white, size: 30),
              onPressed: () {
                final newPosition =
                    _controller.value.position - Duration(seconds: 10);
                _controller.seekTo(
                  newPosition > Duration.zero ? newPosition : Duration.zero,
                );
              },
            ),
            IconButton(
              icon: Icon(
                _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
                size: 40,
              ),
              onPressed: () {
                setState(() {
                  _controller.value.isPlaying
                      ? _controller.pause()
                      : _controller.play();
                });
              },
            ),
            IconButton(
              icon: Icon(Icons.forward_10, color: Colors.white, size: 30),
              onPressed: () {
                final newPosition =
                    _controller.value.position + Duration(seconds: 10);
                _controller.seekTo(newPosition);
              },
            ),
          ],
        ),

        // Progress bar
        VideoProgressIndicator(
          _controller,
          allowScrubbing: true,
          colors: const VideoProgressColors(
            playedColor: Colors.red,
            bufferedColor: Colors.grey,
            backgroundColor: Colors.white24,
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingWidget() {
    return Container(
      height: 200,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text('Loading video...', style: TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Container(
      height: 200,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: Colors.red, size: 50),
            SizedBox(height: 16),
            Text('Failed to load video', style: TextStyle(color: Colors.white)),
            SizedBox(height: 8),
            Text(
              'Path: ${widget.videoPath}',
              style: TextStyle(color: Colors.white54, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: _initializeVideoPlayer,
              child: Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
