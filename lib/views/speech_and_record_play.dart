import 'dart:developer';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_recognition_result.dart' as stt;

import 'dart:async';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class RecordingTextScreen extends StatefulWidget {
  final String? userId;
  const RecordingTextScreen({Key? key, this.userId}) : super(key: key);

  @override
  _RecordingTextScreenState createState() => _RecordingTextScreenState();
}

class _RecordingTextScreenState extends State<RecordingTextScreen> {
  FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  bool _isRecording = false;
  bool _isPlaying = false;
  bool _isTranscribing = false;
  bool _isRecorderInitialized = false;
  String _text = "Hold the button and start speaking";
  String _audioPath = '';
  late AudioRecorder audioRecord;
  late stt.SpeechToText speechToText;
  late AudioPlayer audioPlayer;
  StreamSubscription<stt.SpeechRecognitionResult>? _speechSubscription;

  @override
  void initState() {
    super.initState();
    audioRecord = AudioRecorder();
    speechToText = stt.SpeechToText();
    audioPlayer = AudioPlayer();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _initializeRecorder();
    await _initializeSpeechToText();
  }

  Future<void> _initializeRecorder() async {
    try {
      // Request microphone permission
      var status = await Permission.microphone.request();
      if (status != PermissionStatus.granted) {
        setState(() {
          _text = "Microphone permission denied";
        });
        return;
      }

      // Initialize flutter_sound recorder
      _recorder = FlutterSoundRecorder();

      // Open the recorder with proper error handling
      await _recorder!
          .openRecorder()
          .then((value) {
            setState(() {
              _isRecorderInitialized = true;
              _text = "Ready to record. Hold the button and start speaking";
            });
            if (kDebugMode) {
              log('Recorder initialized successfully');
            }
          })
          .catchError((error) {
            if (kDebugMode) {
              log('Error initializing recorder: $error');
            }
            setState(() {
              _text = "Error initializing audio recorder";
            });
          });
    } catch (e) {
      if (kDebugMode) {
        log('Error in recorder initialization: $e');
      }
      setState(() {
        _text = "Failed to initialize audio recorder";
      });
    }
  }

  Future<void> _initializeSpeechToText() async {
    try {
      bool available = await speechToText.initialize(
        onStatus: (status) {
          if (kDebugMode) {
            log('Speech recognition status: $status');
          }
        },
        onError: (error) {
          if (kDebugMode) {
            log('Speech recognition error: $error');
          }
          setState(() {
            _text = "Speech recognition error: $error";
          });
        },
      );

      if (available) {
        if (kDebugMode) {
          log('Speech to text initialized successfully');
        }
      } else {
        setState(() {
          _text = "Speech recognition not available";
        });
      }
    } catch (e) {
      if (kDebugMode) {
        log('Error initializing speech to text: $e');
      }
    }
  }

  @override
  void dispose() {
    _recorder.closeRecorder();
    audioPlayer.dispose();
    _speechSubscription?.cancel();
    super.dispose();
  }

  // Future<void> startRecording() async {
  //   try {
  //     // Get temporary directory for storing the audio file
  //     final directory = await getTemporaryDirectory();
  //     _audioPath =
  //         '${directory.path}/recording_${DateTime.now().millisecondsSinceEpoch}.aac';

  //     bool permissionGranted = await audioRecord.hasPermission();

  //     if (permissionGranted) {
  //       // Start speech recognition
  //       await speechToText.listen(
  //         onResult: (result) {
  //           if (result.finalResult) {
  //             setState(() {
  //               _text = result.recognizedWords;
  //             });
  //           }
  //         },
  //         listenFor: Duration(minutes: 5),
  //         pauseFor: Duration(seconds: 3),
  //       );

  //       // Start audio recording
  //       await _recorder.startRecorder(toFile: _audioPath);

  //       setState(() {
  //         _isRecording = true;
  //         _text = "Listening...";
  //       });
  //     } else {
  //       setState(() {
  //         _text = "Microphone permission denied";
  //       });
  //     }
  //   } catch (e) {
  //     if (kDebugMode) {
  //       log('Error starting recording: $e');
  //     }
  //     setState(() {
  //       _text = "Error starting recording";
  //     });
  //   }
  // }

  Future<void> startRecording() async {
    try {
      // Get temporary directory for storing the audio file
      final directory = await getTemporaryDirectory();
      _audioPath =
          '${directory.path}/recording_${DateTime.now().millisecondsSinceEpoch}.aac';

      bool permissionGranted = await audioRecord.hasPermission();

      if (permissionGranted) {
        // Start audio recording
        await _recorder.startRecorder(toFile: _audioPath);

        setState(() {
          _isRecording = true;
          _text = "Recording... Speak now";
        });
      } else {
        setState(() {
          _text = "Microphone permission denied";
        });
      }
    } catch (e) {
      if (kDebugMode) {
        log('Error starting recording: $e');
      }
      setState(() {
        _text = "Error starting recording";
      });
    }
  }

  // Future<void> stopRecording() async {
  //   try {
  //     // Stop speech recognition
  //     await speechToText.stop();

  //     // Stop audio recording
  //     await _recorder.stopRecorder();

  //     setState(() {
  //       _isRecording = false;
  //     });

  //     // Transcribe the recorded audio for better accuracy
  //     await _transcribeAudio();
  //   } catch (e) {
  //     if (kDebugMode) {
  //       log('Error stopping recording: $e');
  //     }
  //   }
  // }

  Future<void> stopRecording() async {
    try {
      // Stop audio recording
      await _recorder.stopRecorder();

      setState(() {
        _isRecording = false;
        _text = "Recording stopped. Tap play to transcribe";
      });
    } catch (e) {
      if (kDebugMode) {
        log('Error stopping recording: $e');
      }
    }
  }

  // Future<void> playRecording() async {
  //   try {
  //     if (_audioPath.isNotEmpty) {
  //       setState(() {
  //         _isPlaying = true;
  //       });

  //       await audioPlayer.play(DeviceFileSource(_audioPath));

  //       audioPlayer.onPlayerComplete.listen((event) {
  //         setState(() {
  //           _isPlaying = false;
  //         });
  //       });
  //     }
  //   } catch (e) {
  //     if (kDebugMode) {
  //       log('Error playing recording: $e');
  //     }
  //     setState(() {
  //       _isPlaying = false;
  //     });
  //   }
  // }

  Future<void> playRecording() async {
    if (_audioPath.isEmpty) return;

    try {
      setState(() {
        _isPlaying = true;
        _isTranscribing = true;
        _text = "Transcribing audio... Please wait";
      });

      // Start transcription process
      await _transcribeAudioDuringPlayback();

      // Start audio playback
      await audioPlayer.play(DeviceFileSource(_audioPath));

      audioPlayer.onPlayerComplete.listen((event) {
        setState(() {
          _isPlaying = false;
          _isTranscribing = false;
        });
      });
    } catch (e) {
      if (kDebugMode) {
        log('Error playing recording: $e');
      }
      setState(() {
        _isPlaying = false;
        _isTranscribing = false;
        _text = "Error playing recording";
      });
    }
  }

  Future<void> _transcribeAudioDuringPlayback() async {
    try {
      // First, check if we have permission to use the microphone
      // (even though we're playing back, we need mic access for speech recognition)
      bool hasPermission = await audioRecord.hasPermission();
      if (!hasPermission) {
        setState(() {
          _text = "Microphone permission required for transcription";
          _isTranscribing = false;
        });
        return;
      }

      log("after hasPermission");

      // Initialize speech recognition if not already done
      bool isInitialized = await speechToText.initialize();
      if (!isInitialized) {
        log("after hasPermission !isInitialized");

        setState(() {
          _text = "Speech recognition not available";
          _isTranscribing = false;
        });
        return;
      }

      // Start listening for speech recognition during playback
      await speechToText.listen(
        onResult: (result) {
          log("speechToText listen result");

          if (result.finalResult) {
            log("speechToText listen result if");

            setState(() {
              _text = result.recognizedWords;
              _isTranscribing = false;
            });
          } else if (result.recognizedWords.isNotEmpty) {
            log("speechToText listen result result.recognizedWords.isNotEmpty");

            setState(() {
              _text = result.recognizedWords;
            });
          }
        },
        listenFor: Duration(minutes: 5),
        pauseFor: Duration(seconds: 3),
        onSoundLevelChange: (level) {
          // Optional: You can use this for visual feedback
        },
      );
    } catch (e) {
      if (kDebugMode) {
        log('Error in transcription: $e');
      }
      setState(() {
        _text = "Transcription failed";
        _isTranscribing = false;
      });
    }
  }

  // Future<void> stopPlaying() async {
  //   try {
  //     await audioPlayer.stop();
  //     setState(() {
  //       _isPlaying = false;
  //     });
  //   } catch (e) {
  //     if (kDebugMode) {
  //       log('Error stopping playback: $e');
  //     }
  //   }
  // }

  Future<void> stopPlaying() async {
    try {
      await audioPlayer.stop();
      await speechToText.stop(); // Stop speech recognition
      setState(() {
        _isPlaying = false;
        _isTranscribing = false;
      });
    } catch (e) {
      if (kDebugMode) {
        log('Error stopping playback: $e');
      }
    }
  }

  Future<void> _transcribeAudioFile() async {
    // Alternative approach: If you want to transcribe the file directly
    // without real-time playback, you would need a different approach.
    // The speech_to_text package is designed for real-time audio input,
    // not file processing. For file-based transcription, consider:
    // 1. Google Cloud Speech-to-Text API
    // 2. Azure Speech Services
    // 3. Other cloud-based transcription services
  }

  // Future<void> startRecording() async {
  //   bool permissionGranted = await audioRecord.hasPermission();

  //   // _audioPath = '/path/to/audio.aac';

  //   if (permissionGranted) {
  //     await _recorder.startRecorder(toFile: _audioPath);
  //     setState(() {
  //       _isRecording = true;
  //     });
  //   }
  // }

  // Future<void> stopRecording() async {
  //   await _recorder.stopRecorder();
  //   setState(() {
  //     _isRecording = false;
  //   });
  //   await _transcribeAudio();
  // }

  void checkMicrophoneAvailability() async {
    bool available = await speechToText.initialize();
    if (available) {
      setState(() {
        if (kDebugMode) {
          log('Microphone available: $available');
        }
      });
    } else {
      if (kDebugMode) {
        log("The user has denied the use of speech recognition.");
      }
    }
  }

  Future<void> _transcribeAudio() async {
    try {
      setState(() {
        _text = "Transcribing...";
      });

      // Use speech_to_text package to transcribe the recorded audio file
      // Note: The speech_to_text package primarily does real-time transcription
      // For file-based transcription, you might need additional processing

      // Since speech_to_text is better for real-time, we'll use the results
      // captured during recording. For better accuracy with pre-recorded files,
      // you might want to consider a cloud service like Google Speech-to-Text

      // The real-time transcription is already captured in startRecording()
      // via the listen() method's onResult callback

      if (_text == "Listening..." || _text.isEmpty) {
        setState(() {
          _text = "No speech detected or transcription failed";
        });
      }
    } catch (e) {
      if (kDebugMode) {
        log('Error in transcription: $e');
      }
      setState(() {
        _text = "Transcription failed";
      });
    }
  }

  // Future<void> _transcribeAudio() async {
  //   // checkMicrophoneAvailability();
  //   // final accountCredentials = ServiceAccountCredentials.fromJson(
  //   //   json.decode(await File('path/to/your/credentials.json').readAsString()),
  //   // );

  //   // final scopes = [speech.SpeechApi.cloudPlatformScope];
  //   // final client = await clientViaServiceAccount(accountCredentials, scopes);

  //   // final api = speech.SpeechApi(client);
  //   // final request = speech.RecognizeRequest.fromJson({
  //   //   'config': {
  //   //     'encoding': 'LINEAR16',
  //   //     'sampleRateHertz': 16000,
  //   //     'languageCode': 'en-US',
  //   //   },
  //   //   'audio': {'content': base64Encode(File(_audioPath).readAsBytesSync())},
  //   // });

  //   // final response = await api.speech.recognize(request);
  //   // setState(() {
  //   //   _text =
  //   //       response.results?.first.alternatives?.first.transcript ??
  //   //       'No transcription';
  //   // });
  // }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Channel 3')),
      body: Center(
        child: Column(
          children: [
            SingleChildScrollView(
              reverse: true,
              physics: const BouncingScrollPhysics(),
              child: Container(
                width: MediaQuery.of(context).size.width,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                child: Column(
                  children: [
                    if (_isTranscribing)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: CircularProgressIndicator(),
                      ),
                    SelectableText(
                      _text,
                      style: TextStyle(
                        fontSize: 18,
                        color: _isRecording
                            ? Colors.red
                            : _isTranscribing
                            ? Colors.blue
                            : Colors.black87,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),

            // Recording button
            IconButton(
              icon: Icon(
                _isRecording ? Icons.stop : Icons.mic,
                color: _isRecording ? Colors.red : Colors.blue,
                size: 50,
              ),
              onPressed: _isRecording ? stopRecording : startRecording,
            ),

            SizedBox(height: 20),

            // Playback/Transcribe button
            if (_audioPath.isNotEmpty && !_isRecording)
              IconButton(
                icon: Icon(
                  _isPlaying ? Icons.stop : Icons.play_arrow,
                  color: _isPlaying ? Colors.red : Colors.green,
                  size: 40,
                ),
                onPressed: _isPlaying ? stopPlaying : playRecording,
              ),

            SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
