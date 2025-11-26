import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:push_to_talk_app/core/helpers/paths.dart';
import 'package:push_to_talk_app/presentation/pages/audio_record/controller/audio_player_controller.dart';
import 'package:push_to_talk_app/presentation/pages/audio_record/models/recording.dart';
import 'package:push_to_talk_app/presentation/pages/audio_record/models/recording_group.dart';
part 'files_state.dart';

class FilesCubit extends Cubit<FilesState> {
  FilesCubit() : super(FilesInitial()) {
    getFiles();
  }

  Future<void> getFiles() async {
    List<Recording> recordings = [];
    emit(FilesLoading());

    try {
      // ✅ Use the helper that handles permissions + folder creation
      final Directory recordingsDir = await createSafeRecordingDir();

      final List<FileSystemEntity> files = recordingsDir.listSync();

      for (final file in files) {
        if (file is File) {
          AudioPlayerController controller = AudioPlayerController();

          // Get duration safely
          Duration? fileDuration = await controller.setPath(
            filePath: file.path,
          );

          if (fileDuration != null) {
            recordings.add(Recording(file: file, fileDuration: fileDuration));
          }
        }
      }

      emit(FilesLoaded(recordings: recordings));
    } on Exception catch (e) {
      print("⚠️ Error loading recordings: $e");
      emit(FilesPermisionNotGranted());
    }
  }

  removeRecording(Recording recording) {
    final recordings = (state as FilesLoaded).recordings
        .where((element) => element != recording)
        .toList();
    emit(FilesLoaded(recordings: recordings));
  }
}
