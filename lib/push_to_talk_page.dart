import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class PushToTalkCamera extends StatefulWidget {
  const PushToTalkCamera({super.key});

  @override
  State<PushToTalkCamera> createState() => _PushToTalkCameraState();
}

class _PushToTalkCameraState extends State<PushToTalkCamera> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isCameraOn = false;

  @override
  void initState() {
    super.initState();
    _initCameras();
  }

  Future<void> _initCameras() async {
    _cameras = await availableCameras();
  }

  Future<void> _startCamera() async {
    if (_cameras == null || _cameras!.isEmpty) return;

    _controller = CameraController(_cameras!.first, ResolutionPreset.medium);
    await _controller!.initialize();
    if (!mounted) return;
    setState(() => _isCameraOn = true);
  }

  Future<void> _stopCamera() async {
    await _controller?.dispose();
    setState(() {
      _isCameraOn = false;
      _controller = null;
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          if (_isCameraOn &&
              _controller != null &&
              _controller!.value.isInitialized)
            CameraPreview(_controller!),
          Align(
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              onTapDown: (_) => _startCamera(),
              onTapUp: (_) => _stopCamera(),
              onTapCancel: () => _stopCamera(),
              child: Container(
                margin: const EdgeInsets.all(24),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.camera_alt,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
