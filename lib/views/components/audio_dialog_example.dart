import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:flutter_sound/public/flutter_sound_player.dart';
import 'package:intl/intl.dart';

class AudioDialogExample extends StatefulWidget {
  final String audioPath; // e.g., 'assets/audio/sample.mp3' or a file path

  const AudioDialogExample({Key? key, required this.audioPath})
    : super(key: key);

  @override
  State<AudioDialogExample> createState() => _AudioDialogExampleState();
}

class _AudioDialogExampleState extends State<AudioDialogExample> {
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  bool _isPlaying = false;
  double _progress = 0.0;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player.openPlayer();
    _player.setSubscriptionDuration(const Duration(milliseconds: 500));
    _player.onProgress!.listen((event) {
      if (_duration.inMilliseconds == 0) {
        _duration = event.duration;
      }
      setState(() {
        _position = event.position;
        _progress = _position.inMilliseconds / _duration.inMilliseconds;
      });
    });
  }

  @override
  void dispose() {
    _player.closePlayer();
    super.dispose();
  }

  Future<void> _playPause() async {
    if (_isPlaying) {
      await _player.pausePlayer();
      setState(() => _isPlaying = false);
    } else {
      await _player.startPlayer(
        fromURI: widget.audioPath,
        codec: Codec.aacADTS,
        whenFinished: () {
          setState(() {
            _isPlaying = false;
            _progress = 0.0;
            _position = Duration.zero;
          });
        },
      );
      setState(() => _isPlaying = true);
    }
  }

  String _formatTime(Duration d) {
    final ms = d.inMilliseconds;
    final seconds = (ms / 1000).truncate();
    final minutes = (seconds / 60).truncate();
    final remainingSeconds = seconds % 60;
    return NumberFormat("00").format(minutes) +
        ":" +
        NumberFormat("00").format(remainingSeconds);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: Colors.white,
      title: const Text('Playing Audio'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            iconSize: 48,
            icon: Icon(
              _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
            ),
            onPressed: _playPause,
          ),
          Slider(
            value: _progress.isNaN ? 0.0 : _progress,
            onChanged: (v) async {
              if (_duration.inMilliseconds > 0) {
                final newPosition = (_duration.inMilliseconds * v).toInt();
                await _player.seekToPlayer(Duration(milliseconds: newPosition));
              }
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatTime(_position)),
              Text(_formatTime(_duration)),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await _player.stopPlayer();
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Close'),
        ),
      ],
    );
  }
}
