import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:push_to_talk_app/core/constants/constants.dart';
import 'package:push_to_talk_app/presentation/pages/record_audio_firebase/microphone.dart';
import 'package:push_to_talk_app/presentation/pages/record_audio_firebase/recording_stream.dart';
import 'package:push_to_talk_app/presentation/welcome_screen.dart';

class WalkieTalkieScreen extends StatefulWidget {
  static const String id = 'walkie_screen';

  @override
  _WalkieTalkieScreenState createState() => _WalkieTalkieScreenState();
}

class _WalkieTalkieScreenState extends State<WalkieTalkieScreen> {
  bool isRecording = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: isRecording ? kColourIsRecording : kColourPrimary,
      appBar: AppBar(
        title: Text(kAppTitle, style: kTextStyleAppTitle),
        automaticallyImplyLeading: false,
        actions: <Widget>[
          ElevatedButton(
            child: Text('Sign out', style: kTextStyleLogOutButton),
            style: ElevatedButton.styleFrom(backgroundColor: kColourBackground),
            onPressed: () {
              FirebaseAuth.instance.signOut();
              Navigator.pushNamedAndRemoveUntil(
                context,
                WelcomeScreen.id,
                (route) => false, // Remove all routes
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Container(
          color: kColourBackground,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              RecordingsStream(),
              Microphone(
                isRecording: isRecording,
                onStartRecording: () {
                  setState(() {
                    isRecording = true;
                  });
                },
                onStopRecording: () {
                  setState(() {
                    isRecording = false;
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
