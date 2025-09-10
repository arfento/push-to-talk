import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

class PushToTalkButton extends StatefulWidget {
  const PushToTalkButton({super.key});

  @override
  State<PushToTalkButton> createState() => _PushToTalkButtonState();
}

class _PushToTalkButtonState extends State<PushToTalkButton> {
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  // late IOWebSocketChannel channel;
  String _info = '';
  String _currentActivity = 'stopped';
  int _loopCount = 0;
  bool _inTest = false;
  final SpeechToText _speechToText = SpeechToText();
  final AudioPlayer _player = AudioPlayer();
  @override
  void initState() {
    super.initState();
    _init();
  }

  void _init() async {
    _info += "Init speech\n";
    await _speechToText.initialize(onError: _onError, onStatus: _onStatus);
    // _player.onStop = _onPlayerStop;
    setState(() {});
  }

  void _loopTest() async {
    if (!_inTest) {
      setState(() {
        _currentActivity = 'stopped';
      });
      return;
    }
    _info = "***** Starting loop test ***** \n";

    _info += "Open Audio Session\n";
    String testAudioAsset = 'sounds/notification.m4r';
    logIt('Playing $testAudioAsset');
    await _player.play(UrlSource(testAudioAsset));

    _info += "Start Player\n";

    setState(() {
      _currentActivity = 'playing';
    });
  }

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        // Connect to your WebSocket server
        // channel = IOWebSocketChannel.connect('ws://your_server_url:port');

        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.pcm16bits),
          // path: 'audio.m4a',
          path: '/dev/null',
        ); // Or a temporary path
        setState(() {
          _isRecording = true;
        });
        // // Listen for incoming audio from the server
        // channel.stream.listen((audioData) {
        //   // Process and play back the audio data
        // });
      }
    } catch (e) {
      print('Error starting recording: $e');
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _audioRecorder.stop();
      setState(() {
        _isRecording = false;
      });
      if (path != null) {
        print('Recording saved to: $path');
        // TODO: Implement sending the audio file or streaming the audio data
      }
    } catch (e) {
      print('Error stopping recording: $e');
    }
  }

  Future<void> requestPermission() async {
    var status = await Permission.microphone.status;
    if (!status.isGranted) {
      await Permission.microphone.request();
    }
  }

  @override
  void dispose() {
    _audioRecorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (_) => _startRecording(),
      onLongPressEnd: (_) => _stopRecording(),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _isRecording ? Colors.red : Colors.blue,
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.mic, color: Colors.white, size: 50),
      ),
    );
  }

  void _onStatus(String status) async {
    logIt('onStatus: $status');
    _info += "Speech Status: ${status}\n";
    if (_inTest && status == SpeechToText.doneStatus) {
      logIt('listener stopped');
      // await _speechToText.stop();
      // print('speech stopped');
      _loopTest();
    }
    setState(() {});
  }

  void _onError(SpeechRecognitionError errorNotification) {
    _info += "Error: ${errorNotification.errorMsg}\n";
    setState(() {});
  }

  void _onPlayerStop() async {
    logIt('Player stopped');
    _currentActivity = 'listening';
    ++_loopCount;
    // await Future.delayed(Duration(seconds: 1));
    _speechToText.listen(listenFor: Duration(seconds: 5));
    setState(() {});
  }

  void logIt(String message) {
    final now = DateTime.now();
    debugPrint('SoundLoop: $now, $message');
    _info += message + '\n';
  }
}
