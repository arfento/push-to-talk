import 'package:flutter/material.dart';
import 'package:push_to_talk_app/views/sound_player.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

class AudioPlayerInteraction extends StatefulWidget {
  const AudioPlayerInteraction({Key? key}) : super(key: key);

  @override
  _AudioPlayerInteractionState createState() => _AudioPlayerInteractionState();
}

class _AudioPlayerInteractionState extends State<AudioPlayerInteraction> {
  final SpeechToText _speechToText = SpeechToText();
  final SoundPlayer _player = AudioSoundPlayer();

  // ignore: unused_field
  String _info = '';
  String _currentActivity = 'stopped';
  int _loopCount = 0;
  bool _inTest = false;

  @override
  void initState() {
    super.initState();
    _init();
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
    String testAudioAsset = 'sounds/speech_to_text_cancel.m4r';
    logIt('Playing $testAudioAsset');
    await _player.play(testAudioAsset, loop: false);

    _info += "Start Player\n";

    setState(() {
      _currentActivity = 'playing';
    });
  }

  void _init() async {
    _info += "Init speech\n";
    await _speechToText.initialize(onError: _onError, onStatus: _onStatus);
    _player.onStop = _onPlayerStop;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Audio player")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: _inTest
                      ? null
                      : () {
                          _inTest = true;
                          _loopTest();
                        },
                  child: Text('Loop test'),
                ),
              ],
            ),
            TextButton(
              onPressed: _inTest
                  ? () {
                      _inTest = false;
                    }
                  : null,
              child: Text('End Test'),
            ),
            Expanded(
              child: Column(
                children: [
                  Divider(),
                  Text('Currently: $_currentActivity'),
                  Text('Loops: $_loopCount'),
                ],
              ),
            ),
          ],
        ),
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
    _speechToText.listen(
      listenOptions: SpeechListenOptions(
        // listenFor: Duration(seconds: 5)
      ),
    );
    setState(() {});
  }

  void logIt(String message) {
    final now = DateTime.now();
    debugPrint('SoundLoop: $now, $message');
    _info += message + '\n';
  }
}
