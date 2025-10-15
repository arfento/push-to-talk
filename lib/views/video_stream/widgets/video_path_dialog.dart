import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/services.dart';

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
  bool _isFullscreen = false;

  @override
  void initState() {
    super.initState();
    _initializeVideoPlayer();
  }

  Future<void> _initializeVideoPlayer() async {
    try {
      final file = File(widget.videoPath);
      if (!await file.exists()) {
        setState(() => _hasError = true);
        return;
      }

      _controller = VideoPlayerController.file(file)
        ..initialize().then((_) {
          if (mounted) {
            setState(() => _isInitialized = true);
          }
          _controller
            ..play()
            ..setLooping(true);
        })
        ..addListener(() {
          if (mounted) setState(() {});
        });
    } catch (e) {
      print('❌ Error initializing video player: $e');
      if (mounted) setState(() => _hasError = true);
    }
  }

  @override
  void dispose() {
    if (_isInitialized) _controller.dispose();
    _restoreSystemUI();
    super.dispose();
  }

  /// Enter fullscreen mode with orientation and UI changes
  void _enterFullscreen() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    if (mounted) {
      Navigator.of(context)
          .push(
            PageRouteBuilder(
              opaque: false,
              barrierDismissible: false,
              pageBuilder: (_, __, ___) {
                return Scaffold(
                  backgroundColor: Colors.black,
                  body: SafeArea(child: _buildVideoPlayer(fullscreen: true)),
                );
              },
            ),
          )
          .then((_) => _exitFullscreen());
    }
  }

  /// Exit fullscreen and restore system UI/orientation
  Future<void> _exitFullscreen() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    if (mounted) setState(() {});
  }

  Future<void> _restoreSystemUI() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    // If landscape and fullscreen, show fullscreen scaffold
    if (_isFullscreen || isLandscape) {
      return _buildFullscreen(context);
    }

    // Otherwise, show normal dialog
    return _buildDialog(context);
  }

  /// ----------- NORMAL DIALOG MODE -----------
  Widget _buildDialog(BuildContext context) {
    final dialogContent = _hasError
        ? _buildErrorWidget()
        : !_isInitialized
        ? _buildLoadingWidget()
        : _buildVideoPlayer();

    return Dialog(
      backgroundColor: Colors.black,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxHeight = constraints.maxHeight * 0.9;
          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight, minWidth: 280),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
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
                    const SizedBox(height: 12),
                    dialogContent,
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// ----------- FULLSCREEN MODE -----------
  Widget _buildFullscreen(BuildContext context) {
    final fullscreenContent = _hasError
        ? _buildErrorWidget()
        : !_isInitialized
        ? _buildLoadingWidget()
        : _buildVideoPlayer(fullscreen: true);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(child: fullscreenContent),
            Positioned(
              top: 16,
              right: 16,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () async {
                  await _exitFullscreen();
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ----------- VIDEO PLAYER -----------
  Widget _buildVideoPlayer({bool fullscreen = false}) {
    final aspectRatio = _controller.value.aspectRatio == 0
        ? 16 / 9
        : _controller.value.aspectRatio;

    final video = AspectRatio(
      aspectRatio: aspectRatio,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(fullscreen ? 0 : 12),
        child: VideoPlayer(_controller),
      ),
    );

    if (!fullscreen) {
      // ───────── Normal Dialog Layout ─────────
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          video,
          const SizedBox(height: 12),
          _buildControls(fullscreen: false),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: VideoProgressIndicator(
              _controller,
              allowScrubbing: true,
              colors: const VideoProgressColors(
                playedColor: Colors.redAccent,
                bufferedColor: Colors.grey,
                backgroundColor: Colors.white24,
              ),
            ),
          ),
        ],
      );
    }

    // ───────── Fullscreen Layout ─────────
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(child: video),

        // Controls overlay
        Positioned(
          bottom: 40,
          left: 0,
          right: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildControls(fullscreen: true),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: VideoProgressIndicator(
                  _controller,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(
                    playedColor: Colors.redAccent,
                    bufferedColor: Colors.grey,
                    backgroundColor: Colors.white24,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildControls({required bool fullscreen}) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      children: [
        IconButton(
          icon: const Icon(Icons.replay_10, color: Colors.white, size: 26),
          onPressed: () {
            final newPosition =
                _controller.value.position - const Duration(seconds: 10);
            _controller.seekTo(
              newPosition > Duration.zero ? newPosition : Duration.zero,
            );
          },
        ),
        IconButton(
          icon: Icon(
            _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
            color: Colors.white,
            size: 36,
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
          icon: const Icon(Icons.forward_10, color: Colors.white, size: 26),
          onPressed: () {
            final newPosition =
                _controller.value.position + const Duration(seconds: 10);
            _controller.seekTo(newPosition);
          },
        ),
        IconButton(
          icon: Icon(
            fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
            color: Colors.white,
            size: 26,
          ),
          onPressed: () {
            fullscreen ? _exitFullscreen() : _enterFullscreen();
          },
        ),
      ],
    );
  }

  Widget _buildLoadingWidget() => SizedBox(
    height: 200,
    child: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          CircularProgressIndicator(color: Colors.white),
          SizedBox(height: 16),
          Text('Loading video...', style: TextStyle(color: Colors.white)),
        ],
      ),
    ),
  );

  Widget _buildErrorWidget() => SizedBox(
    height: 200,
    child: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 50),
          const SizedBox(height: 12),
          const Text(
            'Failed to load video',
            style: TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 6),
          Text(
            'Path: ${widget.videoPath}',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: _initializeVideoPlayer,
            child: const Text('Retry'),
          ),
        ],
      ),
    ),
  );
}
