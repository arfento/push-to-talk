import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:push_to_talk_app/utils/snack_msg.dart';
import 'package:push_to_talk_app/views/video_call/signaling.dart';
import 'package:push_to_talk_app/views/video_call/webrtc_body.dart';

typedef ExecuteCallback = void Function();
typedef ExecuteFutureCallback = Future<void> Function();

class WalkieTalkieVideoCall extends StatefulWidget {
  final String controllerIdCall;
  final String clientIPAdress;
  final bool isInitiator; // Tambahkan parameter ini

  const WalkieTalkieVideoCall({
    super.key,
    required this.controllerIdCall,
    required this.clientIPAdress,
    this.isInitiator = false,
  });

  @override
  State<WalkieTalkieVideoCall> createState() => _WalkieTalkieVideoCallState();
}

class _WalkieTalkieVideoCallState extends State<WalkieTalkieVideoCall> {
  static const _chars =
      'AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz1234567890';
  static final _rnd = Random();

  static String getRandomString(int length) => String.fromCharCodes(
    Iterable.generate(
      length,
      (index) => _chars.codeUnitAt(_rnd.nextInt(_chars.length)),
    ),
  );

  final signaling = Signaling(localDisplayName: getRandomString(20));

  final localRenderer = RTCVideoRenderer();
  final Map<String, RTCVideoRenderer> remoteRenderers = {};
  final Map<String, bool?> remoteRenderersLoading = {};

  final roomIdController = TextEditingController();

  bool localRenderOk = false;
  bool error = false;

  bool _isInitiator = false;
  bool _shouldAutoJoin = false;
  bool _callStarted = false;

  @override
  void initState() {
    super.initState();

    _isInitiator = widget.isInitiator;
    _shouldAutoJoin = widget.isInitiator;

    setState(() {
      roomIdController.text = widget.controllerIdCall;
    });

    roomIdController.addListener(() {
      if (mounted) {
        setState(() {
          //
        });
      }
    });

    signaling.onAddLocalStream = (peerUuid, displayName, stream) {
      setState(() {
        localRenderer.srcObject = stream;
        localRenderOk = stream != null;
      });
    };

    signaling.onAddRemoteStream = (peerUuid, displayName, stream) async {
      final remoteRenderer = RTCVideoRenderer();
      await remoteRenderer.initialize();
      remoteRenderer.srcObject = stream;

      setState(() => remoteRenderers[peerUuid] = remoteRenderer);
    };

    signaling.onRemoveRemoteStream = (peerUuid, displayName) async {
      if (remoteRenderers.containsKey(peerUuid)) {
        remoteRenderers[peerUuid]!.srcObject = null;
        remoteRenderers[peerUuid]!.dispose();

        setState(() {
          remoteRenderers.remove(peerUuid);
          remoteRenderersLoading.remove(peerUuid);
        });
      }

      // 👇 if no more remote users remain, auto hang up
      if (remoteRenderers.isEmpty && mounted) {
        await hangUp(false); // cleanup local stream
        if (mounted) Navigator.pop(context); // back to previous screen
        SnackMsg.showInfo(context, 'the call has ended');
      }
    };

    signaling.onConnectionConnected = (peerUuid, displayName) {
      setState(() => remoteRenderersLoading[peerUuid] = false);
    };

    signaling.onConnectionLoading = (peerUuid, displayName) {
      setState(() => remoteRenderersLoading[peerUuid] = true);
    };

    signaling.onConnectionError = (peerUuid, displayName) async {
      SnackMsg.showError(context, 'Connection failed with $displayName');
      error = true;
      await hangUp(false);
      if (mounted) Navigator.pop(context);
    };

    signaling.onGenericError = (errorText) async {
      SnackMsg.showError(context, errorText);
      error = true;
      await hangUp(false);
      if (mounted) Navigator.pop(context);
    };

    // final uri = Uri.base;
    // print("WalkieTalkieVideoCall message uri : ${uri}");
    // final roomIdFromUrl = uri.queryParameters['roomId'] ?? '';
    // print("WalkieTalkieVideoCall message roomIdFromUrl : ${roomIdFromUrl}");

    // roomIdController.text = roomIdFromUrl;

    initCamera();

    if (_shouldAutoJoin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _autoJoinCall();
      });
    }
  }

  Future<void> _autoJoinCall() async {
    if (_shouldAutoJoin && !_callStarted && localRenderOk) {
      await Future.delayed(const Duration(seconds: 1)); // Tunggu sedikit
      if (mounted) {
        await join();
        setState(() {
          _callStarted = true;
        });
      }
    }
  }

  @override
  void dispose() {
    localRenderer.dispose();
    roomIdController.dispose();

    disposeRemoteRenderers();

    super.dispose();
  }

  Future<void> initCamera() async {
    await localRenderer.initialize();
    await doTry(
      runAsync: () async {
        await signaling.openUserMedia();
        // Setelah camera ready, auto join jika initiator
        if (_shouldAutoJoin && !_callStarted) {
          await _autoJoinCall();
        }
      },
    );
  }

  void disposeRemoteRenderers() {
    for (final remoteRenderer in remoteRenderers.values) {
      remoteRenderer.dispose();
    }

    remoteRenderers.clear();
  }

  Future<void> doTry({
    ExecuteCallback? runSync,
    ExecuteFutureCallback? runAsync,
    ExecuteCallback? onError,
  }) async {
    try {
      runSync?.call();
      await runAsync?.call();
    } catch (e) {
      if (mounted) {
        SnackMsg.showError(context, 'Error: $e');
      }

      onError?.call();
    }
  }

  Future<void> reJoin() async {
    await hangUp(false);
    await join();
  }

  Future<void> join() async {
    setState(() => error = false);

    await signaling.reOpenUserMedia();
    await signaling.join(roomIdController.text);
  }

  Future<void> hangUp(bool exit) async {
    setState(() {
      error = false;

      if (exit) {
        roomIdController.text = '';
      }
    });

    await signaling.hangUp(exit);

    setState(() {
      disposeRemoteRenderers();
    });
  }

  bool isMicMuted() {
    try {
      return signaling.isMicMuted();
    } catch (e) {
      SnackMsg.showError(context, 'Error: $e');
      return true;
    }
  }

  bool isCameraClosed() {
    try {
      return !signaling.isCameraEnabled();
    } catch (e) {
      SnackMsg.showError(context, 'Error: $e');
      return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('')),
      backgroundColor: Colors.black,

      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FutureBuilder<int>(
        future: signaling.cameraCount(),
        initialData: 0,
        builder: (context, cameraCountSnap) => Wrap(
          spacing: 15,
          runSpacing: 15,
          children: [
            if (roomIdController.text.length > 2) ...[
              //               FloatingActionButton(
              //                 tooltip: 'Share room link',
              //                 backgroundColor: Colors.blueAccent,
              //                 child: const Icon(Icons.share),
              //                 onPressed: () async {
              //                   final roomUrl =
              //                       'https://0.0.0.0:8080?roomId=${roomIdController.text}';

              //                   final shareText =
              //                       '''
              // Join my WebRTC room

              // Room ID: ${roomIdController.text}
              // Link: $roomUrl
              // ''';

              //                   await Clipboard.setData(ClipboardData(text: shareText));

              //                   if (mounted) {
              //                     SnackMsg.showInfo(
              //                       context,
              //                       'Room link copied to clipboard!',
              //                     );
              //                   }
              //                 },
              //               ),
            ],
            if (localRenderOk) ...[
              if (signaling.isJoined() &&
                  cameraCountSnap.hasData &&
                  cameraCountSnap.requireData > 1) ...[
                FloatingActionButton(
                  tooltip: 'Switch camera',
                  backgroundColor: Colors.grey,
                  child: const Icon(Icons.switch_video_outlined),
                  onPressed: () async =>
                      await doTry(runAsync: () => signaling.switchCamera()),
                ),
              ],
              FloatingActionButton(
                tooltip: isCameraClosed() ? 'Open camera' : 'Close camera',
                backgroundColor: isCameraClosed()
                    ? Colors.redAccent
                    : Colors.grey,
                child: isCameraClosed()
                    ? const Icon(Icons.videocam_off_outlined)
                    : const Icon(Icons.videocam_outlined),
                onPressed: () => doTry(
                  runSync: () => setState(() => signaling.toggleCamera()),
                ),
              ),
              FloatingActionButton(
                tooltip: isMicMuted() ? 'Un-mute mic' : 'Mute mic',
                backgroundColor: isMicMuted() ? Colors.redAccent : Colors.grey,
                child: isMicMuted()
                    ? const Icon(Icons.mic_off)
                    : const Icon(Icons.mic_outlined),
                onPressed: () =>
                    doTry(runSync: () => setState(() => signaling.muteMic())),
              ),
            ] else ...[
              FloatingActionButton(
                tooltip: 'Open camera',
                backgroundColor: Colors.redAccent,
                child: const Icon(Icons.videocam_off_outlined),
                onPressed: () async =>
                    await doTry(runAsync: () => signaling.reOpenUserMedia()),
              ),
            ],
            if (roomIdController.text.length > 2) ...[
              if (error) ...[
                FloatingActionButton(
                  tooltip: 'Retry call',
                  backgroundColor: Colors.green,
                  child: const Icon(Icons.add_call),
                  onPressed: () async => await doTry(
                    runAsync: () => join(),
                    onError: () => hangUp(false),
                  ),
                ),
              ],
              // if (localRenderOk && signaling.isJoined()) ...[
              //   // FloatingActionButton(
              //   //   tooltip: signaling.isScreenSharing()
              //   //       ? 'Change screen sharing'
              //   //       : 'Start screen sharing',
              //   //   backgroundColor: signaling.isScreenSharing()
              //   //       ? Colors.amber
              //   //       : Colors.grey,
              //   //   child: const Icon(Icons.screen_share_outlined),
              //   //   onPressed: () async =>
              //   //       await doTry(runAsync: () => signaling.screenSharing()),
              //   // ),
              //   // if (signaling.isScreenSharing()) ...[
              //   //   FloatingActionButton(
              //   //     tooltip: 'Stop screen sharing',
              //   //     backgroundColor: Colors.redAccent,
              //   //     child: const Icon(Icons.stop_screen_share_outlined),
              //   //     onPressed: () => signaling.stopScreenSharing(),
              //   //   ),
              //   // ],
              //   // FloatingActionButton(
              //   //   tooltip: 'Hangup',
              //   //   backgroundColor: Colors.red,
              //   //   child: const Icon(Icons.call_end),
              //   //   onPressed: () {
              //   //     Navigator.pop(context);
              //   //     hangUp(false);
              //   //   },
              //   // ),
              //   FloatingActionButton(
              //     tooltip: 'Hangup',
              //     backgroundColor: Colors.red,
              //     child: const Icon(Icons.call_end),
              //     onPressed: () async {
              //       await hangUp(false); // cleanup WebRTC
              //       if (mounted) Navigator.pop(context); // safely go back
              //     },
              //   ),
              // ] else ...[
              //   FloatingActionButton(
              //     tooltip: 'Start call',
              //     backgroundColor: Colors.green,
              //     child: const Icon(Icons.call),
              //     onPressed: () async => await doTry(
              //       runAsync: () => join(),
              //       onError: () {
              //         Navigator.pop(context);

              //         hangUp(false);
              //       },
              //     ),
              //   ),
              // ],
              if (localRenderOk) ...[
                // Tampilkan tombol Start Call hanya untuk callee (bukan initiator)
                if (!_isInitiator && !signaling.isJoined()) ...[
                  FloatingActionButton(
                    tooltip: 'Start call',
                    backgroundColor: Colors.green,
                    child: const Icon(Icons.call),
                    onPressed: () async => await doTry(
                      runAsync: () => join(),
                      onError: () {
                        Navigator.pop(context);
                        hangUp(false);
                      },
                    ),
                  ),
                ],
                // Tampilkan tombol hangup jika sudah join atau sedang dalam call
                if (signaling.isJoined() || _callStarted) ...[
                  FloatingActionButton(
                    tooltip: 'Hangup',
                    backgroundColor: Colors.red,
                    child: const Icon(Icons.call_end),
                    onPressed: () async {
                      await hangUp(false);
                      if (mounted) Navigator.pop(context);
                    },
                  ),
                ],
              ],
            ],
          ],
        ),
      ),
      body: WebRTCBody(
        controller: roomIdController,
        localRenderOk: localRenderOk,
        remoteRenderers: remoteRenderers,
        remoteRenderersLoading: remoteRenderersLoading,
        localRenderer: localRenderer,
        signaling: signaling,
        isInitiator: _isInitiator, // Pass ke body untuk UI yang berbeda
      ),
    );
  }
}
