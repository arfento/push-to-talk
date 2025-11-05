import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:push_to_talk_app/utils/constants/color_constant.dart';
import 'package:push_to_talk_app/utils/constants/concave_decoration.dart';
import 'package:push_to_talk_app/utils/constants/recorder_constants.dart';
import 'package:push_to_talk_app/views/audio_record/screens/record_screen/cubit/record_cubit.dart';
import 'package:push_to_talk_app/views/audio_record/screens/recordings_list/cubit/files_cubit.dart';
import 'package:push_to_talk_app/views/audio_record/screens/recordings_list/recordings_list_screen.dart';

import 'widgets/audio_visualizer.dart';
import 'widgets/mic.dart';

class AudioRecordScreen extends StatelessWidget {
  const AudioRecordScreen({Key? key}) : super(key: key);

  static const routeName = '/audiorecordscreen';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.mainColor,
      body: BlocBuilder<RecordCubit, RecordState>(
        builder: (context, state) {
          if (state is RecordStopped || state is RecordInitial) {
            return SafeArea(
              child: Column(
                children: [
                  SizedBox(height: 15),
                  appTitle(),
                  Spacer(),
                  NeumorphicMic(
                    onTap: () {
                      context.read<RecordCubit>().startRecording();
                    },
                  ),
                  Spacer(),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(context, _customRoute());
                    },
                    child: myNotes(),
                  ),
                  SizedBox(height: 15),
                ],
              ),
            );
          } else if (state is RecordOn) {
            return SafeArea(
              child: Column(
                children: [
                  SizedBox(height: 15),
                  appTitle(),
                  Spacer(),
                  Row(
                    children: [
                      Spacer(),
                      StreamBuilder<double>(
                        initialData: RecorderConstants.decibleLimit,
                        stream: context.read<RecordCubit>().aplitudeStream(),
                        builder: (context, snapshot) {
                          if (snapshot.hasData) {
                            return AudioVisualizer(amplitude: snapshot.data);
                          }
                          if (snapshot.hasError) {
                            return Text(
                              'Visualizer failed to load',
                              style: TextStyle(color: AppColors.accentColor),
                            );
                          } else {
                            return SizedBox();
                          }
                        },
                      ),
                      Spacer(),
                    ],
                  ),
                  Spacer(),
                  GestureDetector(
                    onTap: () {
                      context.read<RecordCubit>().stopRecording();

                      ///We need to refresh [FilesState] after recording is stopped
                      context.read<FilesCubit>().getFiles();
                    },
                    child: Container(
                      decoration: ConcaveDecoration(
                        shape: CircleBorder(),
                        depression: 10,
                        colors: [
                          AppColors.highlightColor,
                          AppColors.shadowColor,
                        ],
                      ),
                      child: Icon(
                        Icons.stop,
                        color: AppColors.accentColor,
                        size: 50,
                      ),
                      height: 100,
                      width: 100,
                    ),
                  ),
                  SizedBox(height: 15),
                ],
              ),
            );
          } else {
            return Center(
              child: Text(
                'An Error occured',
                style: TextStyle(color: AppColors.accentColor),
              ),
            );
          }
        },
      ),
    );
  }

  Text myNotes() {
    return Text(
      'MY NOTES',
      style: TextStyle(
        color: AppColors.accentColor,
        fontSize: 20,
        letterSpacing: 5,
        shadows: [
          Shadow(
            offset: Offset(3, 3),
            blurRadius: 5,
            color: Colors.black.withOpacity(0.2),
          ),
        ],
        //decoration: TextDecoration.underline,
      ),
    );
  }

  Widget appTitle() {
    return Text(
      'Voice Recorder',
      style: TextStyle(
        color: AppColors.accentColor,
        fontSize: 50,
        letterSpacing: 5,
        fontWeight: FontWeight.w200,
        shadows: [
          Shadow(
            offset: Offset(3, 3),
            blurRadius: 5,
            color: Colors.black.withOpacity(0.2),
          ),
        ],
      ),
    );
  }

  Route _customRoute() {
    return PageRouteBuilder(
      transitionDuration: Duration.zero,
      pageBuilder: (context, animation, secondaryAnimation) =>
          RecordingsListScreen(),
    );
  }
}
