import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:push_to_talk_app/bloc/camera_bloc.dart';
import 'package:push_to_talk_app/utils/camera_utils.dart';
import 'package:push_to_talk_app/utils/permission_utils.dart';
import 'package:push_to_talk_app/views/video_stream/pages/camera_page.dart';

class VideoHomePage extends StatefulWidget {
  const VideoHomePage({super.key});
  static const String id = 'video_home_screen';

  @override
  State<VideoHomePage> createState() => _VideoHomePageState();
}

class _VideoHomePageState extends State<VideoHomePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text("Home"), centerTitle: true),
      body: Center(
        child: ElevatedButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => BlocProvider(
                  create: (context) {
                    return CameraBloc(
                      cameraUtils: CameraUtils(),
                      permissionUtils: PermissionUtils(),
                    )..add(const CameraInitialize(recordingLimit: 15));
                  },
                  child: const CameraPage(),
                ),
              ),
            );
          },
          child: const Padding(
            padding: EdgeInsets.all(12.0),
            child: Text("Camera 📷", style: TextStyle(fontSize: 25)),
          ),
        ),
      ),
    );
  }
}
