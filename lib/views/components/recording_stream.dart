import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:push_to_talk_app/utils/constants/constants.dart';
import 'package:push_to_talk_app/views/components/recording_row.dart';

class RecordingsStream extends StatefulWidget {
  @override
  _RecordingsStreamState createState() => _RecordingsStreamState();
}

class _RecordingsStreamState extends State<RecordingsStream> {
  final AudioPlayer audioPlayer = AudioPlayer();
  bool isPlaying = false;
  String? currentlyPlayingFilename;

  @override
  void initState() {
    super.initState();
    audioPlayer.onPlayerComplete.listen((event) {
      setState(() {
        isPlaying = false;
        currentlyPlayingFilename = null;
      });
    });
  }

  @override
  void dispose() {
    audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('walkie')
          .orderBy(
            'timestamp',
            descending: true,
          ) // Changed to timestamp for better ordering
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(kColourPrimary!),
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(child: Text('No recordings found'));
        }

        List<RecordingRow> rows = [];
        for (var document in snapshot.data!.docs) {
          final data = document.data() as Map<String, dynamic>;
          rows.add(
            RecordingRow(
              filename: data['filename'],
              currentlyPlayingFilename:
                  currentlyPlayingFilename, // Removed the ! operator
              onTap: (String filename) {
                if (currentlyPlayingFilename == filename) {
                  stopPlaying();
                } else {
                  startPlaying(filename);
                }
              },
            ),
          );
        }
        return Expanded(child: ListView(children: rows, reverse: true));
      },
    );
  }

  Future<void> startPlaying(String filename) async {
    try {
      final url = await FirebaseStorage.instance
          .ref()
          .child(filename)
          .getDownloadURL();

      await audioPlayer.stop(); // Stop any currently playing audio
      await audioPlayer.play(UrlSource(url));

      setState(() {
        isPlaying = true;
        currentlyPlayingFilename = filename;
      });
    } catch (error) {
      print('Error playing file: $error');
    }
  }

  Future<void> stopPlaying() async {
    try {
      await audioPlayer.stop();
      setState(() {
        isPlaying = false;
        currentlyPlayingFilename = null;
      });
    } catch (error) {
      print("Can't stop playing: $error");
    }
  }
}
