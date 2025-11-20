import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class Paths {
  static String recording =
      '/data/user/0/com.example.push_to_talk_app/recordings';
}

Future<Directory> createSafeRecordingDir() async {
  bool granted = await requestStoragePermission();

  if (!granted) {
    throw Exception("Storage permission not granted");
  }

  Directory baseDir;

  if (Platform.isAndroid) {
    // ✅ Safer for Android 10+
    baseDir =
        await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
  } else {
    baseDir = await getApplicationDocumentsDirectory();
  }

  // Create app folder inside that directory
  final Directory appFolder = Directory(
    '${baseDir.path}/PushToTalk/recordings',
  );

  if (!(await appFolder.exists())) {
    await appFolder.create(recursive: true);
  }

  return appFolder;
}

Future<bool> requestStoragePermission() async {
  var status = await Permission.storage.request();
  return status.isGranted;
}
