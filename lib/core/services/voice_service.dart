import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:udp/udp.dart';

class VoiceService {
  static const int voicePort = 6001;
  FlutterSoundRecorder? _recorder;
  FlutterSoundPlayer? _player;
  UDP? _udpSender;
  UDP? _udpReceiver;
  StreamSubscription? _udpSubscription;
  String targetIp = "192.168.39.48"; // Set this when joining a lobby
  bool isSpeaking = false;

  VoiceService() {
    _recorder = FlutterSoundRecorder();
    _player = FlutterSoundPlayer();
  }

  Future<void> init() async {
    try {
      _recorder = FlutterSoundRecorder();
      _player = FlutterSoundPlayer();

      await _recorder!.openRecorder();
      await _player!.openPlayer();

      _udpSender = await UDP.bind(Endpoint.any());
      _udpReceiver = await UDP.bind(Endpoint.any(port: Port(voicePort)));

      // Check if UDP receiver is initialized before using it
      if (_udpReceiver == null) {
        print("UDP Receiver failed to initialize!");
        return;
      }

      _udpReceiver!.asStream().listen((datagram) {
        if (datagram != null) {
          _player!.startPlayer(
            fromDataBuffer: datagram.data,
            codec: Codec.pcm16,
          );
        }
      });
    } catch (e) {
      print("Error initializing VoiceService: $e");
    }
  }

  /// Start recording and send audio over UDP
  Future<void> startTalking() async {
    if (targetIp.isEmpty) return; // Ensure target IP is set

    isSpeaking = true;
    await _recorder!.startRecorder(
      codec: Codec.pcm16, // Use PCM16 for real-time low-latency transmission
      sampleRate: 16000, // Lower sample rate for smaller packets
      numChannels: 1, // Walkie-talkies use mono audio
      audioSource: AudioSource.microphone,
      toFile: 'audio_chunk.pcm', // Temporarily save recorded chunk
    );

    // Send recorded audio chunks every 200ms
    _sendAudioChunks();
  }

  /// Stop recording
  Future<void> stopTalking() async {
    isSpeaking = false;
    await _recorder!.stopRecorder();
  }

  /// Read and send audio chunks over UDP
  Future<void> _sendAudioChunks() async {
    while (isSpeaking) {
      File audioFile = File('audio_chunk.pcm');
      if (await audioFile.exists()) {
        Uint8List audioData = await audioFile.readAsBytes();
        if (audioData.isNotEmpty && targetIp.isNotEmpty) {
          _udpSender!.send(
            audioData,
            Endpoint.unicast(InternetAddress(targetIp), port: Port(voicePort)),
          );
        }
        await audioFile.delete(); // Delete after sending
      }
      await Future.delayed(
        Duration(milliseconds: 200),
      ); // Adjust delay for smooth transmission
    }
  }

  /// Cleanup resources
  void dispose() {
    _udpSender?.close();
    _udpReceiver?.close();
    _udpSubscription?.cancel();
    _recorder?.closeRecorder();
    _player?.closePlayer();
  }
}
