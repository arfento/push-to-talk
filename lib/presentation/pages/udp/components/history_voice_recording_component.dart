import 'package:flutter/material.dart';
import 'package:push_to_talk_app/presentation/pages/udp/components/voice_recording_tile.dart';
import 'package:push_to_talk_app/data/model/voice_recording_model.dart';

class VoiceHistoryDialog extends StatelessWidget {
  final List<VoiceRecording> recordings;
  final String myIp;
  final Function(VoiceRecording recording, int index) onDelete;

  const VoiceHistoryDialog({
    super.key,
    required this.recordings,
    required this.myIp,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (recordings.isEmpty) {
      Future.microtask(() {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("No voice recordings found")));
      });
    }

    return AlertDialog(
      title: Text('Voice Recordings (${recordings.length})'),
      content: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.6,
        child: ListView.builder(
          itemCount: recordings.length,
          itemBuilder: (context, index) {
            return VoiceRecordingTile(
              recording: recordings[index],
              isMine: recordings[index].senderIp == myIp,
              onDelete: () => onDelete(recordings[index], index),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Close'),
        ),
      ],
    );
  }
}
