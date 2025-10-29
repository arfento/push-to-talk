import 'package:permission_handler/permission_handler.dart';

class PermissionUtils {
  /// Checks the current status of camera and microphone permissions.
  /// Returns `true` if both camera and microphone permissions are granted.
  Future<bool> getCameraAndMicrophonePermissionStatus() async {
    // Get the current status of camera and microphone permissions
    PermissionStatus cameraStatus = await Permission.camera.status;
    PermissionStatus microphoneStatus = await Permission.microphone.status;
    PermissionStatus photosStatus = await Permission.photos.status;
    PermissionStatus audioStatus = await Permission.audio.status;
    PermissionStatus videosStatus = await Permission.videos.status;

    // Check if both camera and microphone permissions are granted
    if (cameraStatus.isGranted && microphoneStatus.isGranted
    // &&
    // videosStatus.isGranted &&
    // photosStatus.isGranted &&
    // audioStatus.isGranted
    ) {
      return true;
    }
    return false;
  }

  /// Requests camera and microphone permissions and returns `true` if granted.
  Future<bool> askForPermission() async {
    // Request camera and microphone permissions
    Map<Permission, PermissionStatus> status = await [
      Permission.camera,
      Permission.microphone,
      Permission.photos,
      Permission.audio,
      Permission.videos,
    ].request();

    // Check if both camera and microphone permissions are granted
    if (status[Permission.camera]!.isGranted &&
        status[Permission.microphone]!.isGranted
    // &&
    // status[Permission.photos]!.isGranted &&
    // status[Permission.audio]!.isGranted &&
    // status[Permission.videos]!.isGranted
    ) {
      return true;
    }
    return false;
  }
}
