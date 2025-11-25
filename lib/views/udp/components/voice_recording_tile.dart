import 'package:flutter/material.dart';
import 'package:push_to_talk_app/views/components/modern_audio_dialog.dart';
import 'package:push_to_talk_app/views/udp/voice_recording_model.dart';

class VoiceRecordingTile extends StatelessWidget {
  final VoiceRecording recording;
  final bool isMine;
  final VoidCallback onDelete;

  const VoiceRecordingTile({
    super.key,
    required this.recording,
    required this.isMine,
    required this.onDelete,
  });

  String _extractSender() {
    if (!recording.fileName.contains('_from_')) return "You";

    final parts = recording.fileName.split('_from_');
    if (parts.length <= 1) return "Unknown";

    return parts[1].replaceAll('.aac', '');
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')} '
        '${dateTime.day}/${dateTime.month}/${dateTime.year}';
  }

  @override
  Widget build(BuildContext context) {
    String sender = _extractSender();

    return Container(
      margin: EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: isMine ? Colors.blue[50] : Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isMine ? Colors.blue[100]! : Colors.grey[300]!,
        ),
      ),
      child: ListTile(
        leading: Icon(
          Icons.audiotrack,
          color: isMine ? Colors.blue : Colors.green,
        ),
        title: Text(
          recording.fileName,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("From: $sender", style: TextStyle(fontSize: 12)),
            Text(
              _formatDateTime(recording.timestamp),
              style: TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(Icons.play_arrow, color: Colors.green),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => ModernAudioDialog(
                    filePath: recording.filePath,
                    sender: recording.senderIp,
                    timestamp: recording.timestamp,
                    isMyRecording: isMine,
                  ),
                );
              },
            ),
            IconButton(
              icon: Icon(Icons.delete, color: Colors.red),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
