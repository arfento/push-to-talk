import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:push_to_talk_app/utils/constants/constants.dart';
import 'package:record/record.dart';

class Microphone extends StatefulWidget {
  final bool isRecording;
  final Function onStartRecording;
  final Function onStopRecording;

  Microphone({
    required this.isRecording,
    required this.onStartRecording,
    required this.onStopRecording,
  });

  @override
  State<Microphone> createState() => _MicrophoneState();
}

class _MicrophoneState extends State<Microphone> {
  final AudioRecorder _audioRecorder = AudioRecorder();
  String? _currentRecordingPath;

  @override
  void dispose() {
    _audioRecorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      child: Container(
        height: 96.0,
        color: widget.isRecording ? kColourIsRecording : kColourPrimary,
        child: Icon(Icons.mic, size: 48.0, color: Colors.white),
      ),
      onTapDown: (TapDownDetails details) {
        _startRecording();
      },
      onTapUp: (TapUpDetails details) {
        _stopRecording();
      },
      onTapCancel: () {
        _stopRecording();
      },
    );
  }

  Future<void> _startRecording() async {
    try {
      if (await _hasPermissions()) {
        widget.onStartRecording();
        String path = await _getFilePath();
        _currentRecordingPath = path;

        await _audioRecorder.start(
          RecordConfig(encoder: AudioEncoder.aacLc),
          path: path,
        );
      }
    } catch (error) {
      print('Recording error: $error');
      widget.onStopRecording();
    }
  }

  Future<void> _stopRecording() async {
    if (widget.isRecording) {
      widget.onStopRecording();

      try {
        final recording = await _audioRecorder.stop();
        if (recording != null && _currentRecordingPath != null) {
          await _sendRecording(_currentRecordingPath!);
        }
      } catch (error) {
        print('Error stopping recording: $error');
      } finally {
        _currentRecordingPath = null;
      }
    }
  }

  Future<void> _sendRecording(String path) async {
    try {
      final fileName = path.split('/').last;
      final file = File(path);

      // Upload to Firebase Storage
      await FirebaseStorage.instance.ref().child(fileName).putFile(file);

      // Add to Firestore
      await FirebaseFirestore.instance.collection('walkie').add({
        'filename': fileName,
        'timestamp': FieldValue.serverTimestamp(),
      });

      // Clean up local file
      await file.delete();
    } catch (error) {
      print('Error sending recording: $error');
    }
  }

  Future<bool> _hasPermissions() async {
    var status = await Permission.microphone.status;
    switch (status) {
      case PermissionStatus.granted:
        return true;
      // case PermissionStatus.undetermined:
      case PermissionStatus.denied:
        Permission.microphone.request();
        break;
      case PermissionStatus.restricted:
        print('Microphone access is restricted. You cannot use this app.');
        break;
      case PermissionStatus.permanentlyDenied:
        print(
          'Microsoft access is permanently denied. '
          'You have to go to Settings to enable it.',
        );
        break;
      case PermissionStatus.limited:
        // TODO: Handle this case.
        throw UnimplementedError();
      case PermissionStatus.provisional:
        // TODO: Handle this case.
        throw UnimplementedError();
    }
    return false;
  }

  Future<String> _getFilePath() async {
    Directory appDocDirectory = await getApplicationDocumentsDirectory();
    String timestamp = DateTime.now().toIso8601String();
    return '${appDocDirectory.path}/recording_$timestamp.m4a';
  }
}
