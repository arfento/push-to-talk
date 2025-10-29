import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'dart:async';

class ModernAudioDialog extends StatefulWidget {
  final String filePath;
  final String sender;
  final DateTime timestamp;
  final bool isMyRecording;

  const ModernAudioDialog({
    Key? key,
    required this.filePath,
    required this.sender,
    required this.timestamp,
    required this.isMyRecording,
  }) : super(key: key);

  @override
  State<ModernAudioDialog> createState() => _ModernAudioDialogState();
}

class _ModernAudioDialogState extends State<ModernAudioDialog> {
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  StreamSubscription? _progressSub;

  bool _isPlaying = false;
  double _position = 0.0;
  double _duration = 0.0;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    await _player.openPlayer();
    _player.setSubscriptionDuration(const Duration(milliseconds: 300));

    _progressSub = _player.onProgress!.listen((event) {
      if (!mounted) return;
      setState(() {
        _position = event.position.inMilliseconds.toDouble();
        _duration = event.duration.inMilliseconds.toDouble();
      });
    });
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    _player.closePlayer();
    super.dispose();
  }

  Future<void> _playPause() async {
    if (_isPlaying) {
      await _player.pausePlayer();
    } else {
      if (!_player.isPlaying) {
        await _player.startPlayer(
          fromURI: widget.filePath,
          codec: Codec.aacADTS,
          whenFinished: () {
            if (mounted) {
              setState(() {
                _isPlaying = false;
                _position = 0.0;
              });
            }
          },
        );
      } else {
        await _player.resumePlayer();
      }
    }

    setState(() => _isPlaying = !_isPlaying);
  }

  Future<void> _stopPlayer() async {
    await _player.stopPlayer();
    if (mounted) Navigator.pop(context);
  }

  String _formatTime(double ms) {
    final duration = Duration(milliseconds: ms.toInt());
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return "${twoDigits(duration.inMinutes.remainder(60))}:${twoDigits(duration.inSeconds.remainder(60))}";
  }

  @override
  Widget build(BuildContext context) {
    double progress = _duration > 0
        ? (_position / _duration).clamp(0.0, 1.0)
        : 0.0;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.grey[50],
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Title
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.audiotrack_rounded, color: Colors.blueAccent),
                const SizedBox(width: 8),
                const Text(
                  "Voice Message",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Slider
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              ),
              child: Slider(
                value: _position.clamp(0.0, _duration),
                min: 0.0,
                max: _duration > 0 ? _duration : 1.0,
                activeColor: Colors.blueAccent,
                inactiveColor: Colors.grey[300],
                onChanged: (v) async {
                  await _player.seekToPlayer(Duration(milliseconds: v.toInt()));
                },
              ),
            ),

            // Time indicators
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatTime(_position),
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  _formatTime(_duration),
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Play/Pause button
            GestureDetector(
              onTap: _playPause,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, anim) =>
                    ScaleTransition(scale: anim, child: child),
                child: _isPlaying
                    ? const Icon(
                        Icons.pause_circle_filled,
                        key: ValueKey("pause"),
                        size: 64,
                        color: Colors.blueAccent,
                      )
                    : const Icon(
                        Icons.play_circle_fill,
                        key: ValueKey("play"),
                        size: 64,
                        color: Colors.blueAccent,
                      ),
              ),
            ),

            const SizedBox(height: 16),

            // Sender & Date info
            Column(
              children: [
                Text(
                  'From: ${widget.isMyRecording ? 'You' : widget.sender}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  _formatTimestamp(widget.timestamp),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Stop Button
            ElevatedButton.icon(
              onPressed: _stopPlayer,
              icon: const Icon(Icons.stop_circle_rounded),
              label: const Text("Stop"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime time) {
    return "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')} - ${time.day}/${time.month}/${time.year}";
  }
}
