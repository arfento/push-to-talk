import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:push_to_talk_app/bloc/camera_bloc.dart';
import 'package:push_to_talk_app/utils/camera_utils.dart';
import 'package:push_to_talk_app/utils/permission_utils.dart';
import 'package:push_to_talk_app/views/components/audio_dialog_example.dart';
import 'package:push_to_talk_app/views/components/modern_audio_dialog.dart';
import 'package:push_to_talk_app/views/udp/file_transfer.dart';
import 'package:push_to_talk_app/views/udp/voice_recording_model.dart';
import 'package:push_to_talk_app/views/video_stream/pages/camera_page.dart';
import 'package:push_to_talk_app/views/video_stream/widgets/video_path_dialog.dart';
import 'package:udp/udp.dart';
import 'package:flutter_sound/flutter_sound.dart';

class LobbyScreen extends StatefulWidget with WidgetsBindingObserver {
  static const String id = 'lobby_screen';
  final bool isHost;
  final String hostIp; // Host's IP

  const LobbyScreen({super.key, required this.isHost, required this.hostIp});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> with WidgetsBindingObserver {
  // List<String> connectedUsers = []; // Stores connected IPs
  final ValueNotifier<List<String>> _connectedUsersNotifier =
      ValueNotifier<List<String>>([]); // Real-time connected users

  UDP? udpSocket;
  static const int discoveryPort = 5000;
  FlutterSoundRecorder? _audioRecorder;
  FlutterSoundPlayer _audioPlayer = FlutterSoundPlayer();
  bool _isRecording = false;
  String _myIpAddress = '';
  bool _isStreaming = false; // For real-time streaming
  StreamController<Uint8List>? _audioStreamController; // Added for streaming
  Timer? _silenceTimer; // To detect end of stream on receiver
  bool _isPlayerReady = false; // Track if player is ready for streaming

  // Camera variables
  static const int VIDEO_PORT = 6007;

  // TCP Server for file transfer (Host only)
  ServerSocket? _tcpServer;
  static const int TCP_FILE_PORT = 6008;

  // TCP Client for file transfer
  List<Socket> _tcpClients = [];

  // Progress dialog variables
  bool _isSendingFile = false;
  double _fileTransferProgress = 0.0;
  String _currentFileName = '';
  StreamController<double>? _progressController; // Stream for progress updates

  //send & received message
  TextEditingController messageController = TextEditingController();
  List<String> messages = []; // Stores received messages

  List<String> get connectedUsers => _connectedUsersNotifier.value;

  bool _isDisposed = false;
  Timer? _keepAliveTimer;

  // Voice recording history variables
  List<VoiceRecording> _voiceRecordings = [];
  static const int VOICE_PORT = 6011;

  // Voice playing variables
  bool _isPlayingVoice = false;
  VoiceRecording? _currentlyPlayingRecording;
  StreamSubscription? _playbackSubscription;
  double _playbackPosition = 0.0;
  double _playbackDuration = 0.0;
  Timer? _playbackTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    getLocalIp();
    _audioRecorder = FlutterSoundRecorder();
    _audioPlayer = FlutterSoundPlayer();
    _progressController = StreamController<double>.broadcast();

    _initAudio();
    _loadVoiceRecordings(); // Load existing voice recordings

    if (widget.isHost) {
      _startReceivingRequests();
      _startKeepAliveBroadcast();
    } else {
      _sendJoinRequest();
      _startKeepAliveListener();
    }

    _listenForUpdates();
    _listenForMessages();
    _listenForAudio();
    _listenForStreamedAudio(); // New listener for real-time audio
    _listenForVideoStream(); // New listener for video
    _listenForVoiceRecordings(); // Listen for incoming voice recordings

    if (widget.isHost) {
      _startTcpServer();
    }
    _connectToTcpServer();
  }

  Future<String?> getLocalIp() async {
    print("MY IP ADDRESS $_myIpAddress");
    for (var interface in await NetworkInterface.list()) {
      for (var addr in interface.addresses) {
        if (addr.type == InternetAddressType.IPv4 &&
            (addr.address.startsWith("172.16.") ||
                addr.address.startsWith("192.168."))) {
          setState(() {
            _myIpAddress = addr.address;
          });
          print("MY IP ADDRESS $_myIpAddress");
          return addr.address;
        }
      }
    }
    return null;
  }

  // Add keep-alive mechanism
  void _startKeepAliveBroadcast() {
    _keepAliveTimer = Timer.periodic(Duration(seconds: 5), (timer) async {
      if (_isDisposed) {
        timer.cancel();
        return;
      }

      for (String ip in connectedUsers) {
        if (ip != _myIpAddress) {
          try {
            UDP sender = await UDP.bind(Endpoint.any());
            await sender.send(
              Uint8List.fromList("KEEP_ALIVE".codeUnits),
              Endpoint.unicast(InternetAddress(ip), port: Port(6009)),
            );
            sender.close();
          } catch (e) {
            print("❌ Error sending keep-alive to $ip: $e");
          }
        }
      }
    });
  }

  void _startKeepAliveListener() async {
    UDP receiver = await UDP.bind(Endpoint.any(port: Port(6009)));

    receiver.asStream().listen((datagram) {
      if (datagram != null) {
        String message = String.fromCharCodes(datagram.data);
        if (message == "KEEP_ALIVE") {
          // Host is still alive, do nothing
        }
      }
    });

    // Also set up a timer to check if host is still responsive
    Timer.periodic(Duration(seconds: 15), (timer) async {
      if (_isDisposed || widget.isHost) {
        timer.cancel();
        return;
      }

      // Send ping to host
      try {
        UDP sender = await UDP.bind(Endpoint.any());
        await sender.send(
          Uint8List.fromList("PING".codeUnits),
          Endpoint.unicast(InternetAddress(widget.hostIp), port: Port(6010)),
        );
        sender.close();
      } catch (e) {
        print("❌ Host seems to be offline: $e");
        _handleHostDisconnected();
      }
    });
  }

  void _handleHostDisconnected() {
    if (_isDisposed) return;

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text("Host Disconnected"),
          content: Text(
            "The host has left the lobby. You will be returned to the main screen.",
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.popUntil(context, (route) => route.isFirst);
              },
              child: Text("OK"),
            ),
          ],
        ),
      );
    }
  }

  // Enhanced leave handling
  Future<void> _cleanupAndLeave() async {
    if (_isDisposed) return;

    _isDisposed = true;

    // Send leave notification
    if (!widget.isHost && widget.hostIp.isNotEmpty) {
      try {
        UDP sender = await UDP.bind(Endpoint.any());
        await sender.send(
          Uint8List.fromList("LEAVE".codeUnits),
          Endpoint.unicast(InternetAddress(widget.hostIp), port: Port(6002)),
        );
        sender.close();
      } catch (e) {
        print("❌ Error sending leave message: $e");
      }
    }

    // Cleanup audio resources first
    try {
      _silenceTimer?.cancel();
      // await _stopPlayerForStream();
      await _audioRecorder?.closeRecorder();
      await _audioPlayer?.closePlayer();
      _audioStreamController?.close();
    } catch (e) {
      print("❌ Error cleaning up audio resources: $e");
    }
    // Stop streaming if active
    if (_isStreaming) {
      _stopStreaming();
    }
    // Stop recording if active
    if (_isRecording) {
      await _audioRecorder!.stopRecorder();
      setState(() => _isRecording = false);
    }

    // Cleanup other resources
    _keepAliveTimer?.cancel();
    udpSocket?.close();
    _progressController?.close();

    // Close TCP connections
    for (Socket client in _tcpClients) {
      client.destroy();
    }
    await _tcpServer?.close();
    // Send leave notification (if client)
    if (!widget.isHost && widget.hostIp.isNotEmpty) {
      try {
        UDP sender = await UDP.bind(Endpoint.any());
        await sender.send(
          Uint8List.fromList("LEAVE".codeUnits),
          Endpoint.unicast(InternetAddress(widget.hostIp), port: Port(6002)),
        );
        sender.close();
      } catch (e) {
        print("❌ Error sending leave message: $e");
      }
    }
    print("🧹 [CLEANUP] All resources cleaned up successfully");
  }

  Future<void> _initAudio() async {
    await _audioPlayer?.openPlayer();
    await _audioRecorder?.openRecorder();
    await _startPlayerForStream(); // Initial setup
    // try {
    //   await _audioRecorder?.openRecorder();

    //   // Enhanced player initialization with retry logic
    //   await _initializeAudioPlayerWithRetry();

    //   await _startPlayerForStream(); // Initial setup
    // } catch (e) {
    //   print("❌ [AUDIO] Error initializing audio: $e");
    //   // Retry initialization after a delay
    //   await Future.delayed(Duration(seconds: 1));
    //   await _initializeAudioPlayerWithRetry();
    // }
  }

  // Future<void> _initializeAudioPlayerWithRetry() async {
  //   try {
  //     await _audioPlayer?.openPlayer();

  //     // Additional configuration for better compatibility
  //     if (Platform.isAndroid) {
  //       // Set specific configuration for Android devices
  //       await _audioPlayer?.setSubscriptionDuration(Duration(milliseconds: 10));
  //     }
  //   } catch (e) {
  //     print("❌ [AUDIO] Error opening player: $e");
  //     // Recreate the player instance if it fails
  //     _audioPlayer = FlutterSoundPlayer();
  //     await _audioPlayer?.openPlayer();
  //   }
  // }

  void _listenForVideoStream() async {
    UDP receiver = await UDP.bind(Endpoint.any(port: Port(VIDEO_PORT)));
    log(
      "_listenForVideoStream 🎥 [CLIENT] Listening for video stream on port $VIDEO_PORT...",
    );

    Map<String, FileTransfer> fileTransfers = {};

    receiver.asStream().listen((datagram) async {
      if (datagram != null && datagram.data.isNotEmpty) {
        String senderIp = datagram.address.address;
        Uint8List data = datagram.data;

        log(
          '_listenForVideoStream 📹 Received data from $senderIp: ${data.length} bytes',
        );

        try {
          if (data.length >= 12) {
            ByteData headerData = ByteData.view(data.buffer);
            int totalSize = headerData.getUint32(0);
            int chunkIndex = headerData.getUint32(4);
            int totalChunks = headerData.getUint32(8);
            Uint8List videoChunk = data.sublist(12);

            log(
              '_listenForVideoStream 📦 Chunk $chunkIndex/$totalChunks from $senderIp (${videoChunk.length} bytes)',
            );

            // Initialize or get existing transfer
            if (!fileTransfers.containsKey(senderIp)) {
              log(
                '_listenForVideoStream 🆕 Starting new file transfer from $senderIp: $totalChunks chunks, $totalSize bytes',
              );
              fileTransfers[senderIp] = FileTransfer(
                totalSize: totalSize,
                totalChunks: totalChunks,
                chunks: List<Uint8List?>.filled(totalChunks, null),
                receivedChunks: 0,
                lastChunkTime: DateTime.now(),
                timer: Timer(Duration(seconds: 30), () {
                  // Increased timeout
                  log(
                    '_listenForVideoStream ⏰ Timeout for transfer from $senderIp - only received ${fileTransfers[senderIp]?.receivedChunks}/$totalChunks chunks',
                  );
                  fileTransfers.remove(senderIp);
                }),
              );
            }

            FileTransfer transfer = fileTransfers[senderIp]!;

            // Reset timer on each received chunk
            transfer.timer.cancel();
            transfer.timer = Timer(Duration(seconds: 30), () {
              log(
                '_listenForVideoStream ⏰ Timeout for transfer from $senderIp - received ${transfer.receivedChunks}/${transfer.totalChunks} chunks',
              );
              fileTransfers.remove(senderIp);
            });

            // Update chunk if not already received
            if (transfer.chunks[chunkIndex] == null) {
              transfer.chunks[chunkIndex] = videoChunk;
              transfer.receivedChunks++;
              transfer.lastChunkTime = DateTime.now();

              log(
                '_listenForVideoStream ✅ Stored chunk $chunkIndex - Progress: ${transfer.receivedChunks}/${transfer.totalChunks}',
              );
            } else {
              log(
                '_listenForVideoStream 📨 Duplicate chunk $chunkIndex received',
              );
            }

            // Check if we have all chunks
            if (transfer.receivedChunks == transfer.totalChunks) {
              log(
                '_listenForVideoStream 🎉 All chunks received from $senderIp, reassembling file...',
              );

              // Reconstruct file
              Uint8List completeFile = Uint8List(transfer.totalSize);
              int position = 0;
              int actualChunks = 0;

              for (var chunk in transfer.chunks) {
                if (chunk != null) {
                  completeFile.setRange(
                    position,
                    position + chunk.length,
                    chunk,
                  );
                  position += chunk.length;
                  actualChunks++;
                }
              }

              log(
                '_listenForVideoStream 🔧 Reassembled file: $position bytes from $actualChunks chunks',
              );

              // Cancel timeout timer
              transfer.timer.cancel();

              // Save and display video
              await _saveAndDisplayVideo(completeFile, senderIp);

              // Clean up
              fileTransfers.remove(senderIp);

              log(
                '_listenForVideoStream 🎊 Video file successfully processed from $senderIp',
              );
            } else {
              double progress =
                  (transfer.receivedChunks / transfer.totalChunks) * 100;
              log(
                '_listenForVideoStream 📊 Progress: ${transfer.receivedChunks}/${transfer.totalChunks} chunks (${progress.toStringAsFixed(1)}%) from $senderIp',
              );
            }
          } else {
            log(
              "_listenForVideoStream 📹 Real-time video frame from $senderIp: ${data.length} bytes",
            );
          }
        } catch (e) {
          log(
            '_listenForVideoStream ❌ Error processing video data from $senderIp: $e',
          );
        }
      }
    });
  }

  Future<void> _saveAndDisplayVideo(
    Uint8List videoData,
    String senderIp,
  ) async {
    log('sendvideo _listenForVideoStream _saveAndDisplayVideo $senderIp');

    try {
      String tempPath =
          '${Directory.systemTemp.path}/received_video_${DateTime.now().millisecondsSinceEpoch}.mp4';
      await File(tempPath).writeAsBytes(videoData);
      log('sendvideo _listenForVideoStream _saveAndDisplayVideo $tempPath');

      // Show dialog with the received video
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Video Received from $senderIp'),
            content: Text('Video saved to: $tempPath'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (context) => VideoPathDialog(videoPath: tempPath),
                  );
                },
                child: Text('OK'),
              ),
            ],
          ),
        );
      }

      log('sendvideo _listenForVideoStream Video saved to: $tempPath');
    } catch (e) {
      log('sendvideo _listenForVideoStream Error saving video: $e');
    }
  }

  // List all videos in the directory (for debugging)
  Future<void> _listAllVideos() async {
    try {
      String directory = await _getAppDirectory();
      log('sendvideo _listAllVideos directory: $directory');

      final videoDir = Directory(directory);
      log('sendvideo _listAllVideos videoDir: $videoDir');
      if (!await videoDir.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('No videos found')));
        }
        return;
      }

      if (await videoDir.exists()) {
        log('sendvideo _listAllVideos videoDir.exists(): ${videoDir.exists()}');

        List<FileSystemEntity> files = videoDir.listSync();
        List<FileSystemEntity> videoFiles = files
            .where(
              (file) =>
                  file.path.toLowerCase().endsWith('.mp4') ||
                  file.path.toLowerCase().endsWith('.mov'),
            )
            .toList();

        if (videoFiles.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('No videos found')));
          }
          return;
        }

        log("sendvideo 📁 Videos in directory: ${videoFiles.length}");
        for (var file in videoFiles) {
          log("sendvideo   - ${file.path.split('/').last}");
        }

        // Show dialog with video list
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Received Videos (${videoFiles.length})'),
            content: Container(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: videoFiles.length,
                itemBuilder: (context, index) {
                  String fileName = videoFiles[index].path.split('/').last;
                  return ListTile(
                    leading: Icon(Icons.video_library, color: Colors.blue),
                    title: Text(fileName),
                    onTap: () {
                      // Play the video
                      Navigator.pop(context);
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (context) =>
                            VideoPathDialog(videoPath: videoFiles[index].path),
                      );
                      // _playVideo(File(videoFiles[index].path));
                    },
                    trailing: IconButton(
                      icon: Icon(Icons.delete, color: Colors.red),
                      onPressed: () {
                        Navigator.pop(context);
                        _deleteVideo(File(videoFiles[index].path));
                      },
                    ),
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
          ),
        );
      }
    } catch (e) {
      log("sendvideo ❌ Error listing videos: $e");
    }
  }

  // Delete video method
  void _deleteVideo(File videoFile) async {
    try {
      await videoFile.delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Video deleted'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print("❌ Error deleting video: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete video'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _startPlayerForStream() async {
    if (!_isPlayerReady) {
      try {
        // Check if player is actually ready and not disposed
        // if (_audioPlayer?.isStopped ?? true) {
        //   await _audioPlayer?.openPlayer();
        // }

        await _audioPlayer?.startPlayerFromStream(
          codec: Codec.pcm16,
          numChannels: 1, // Changed from 2 to 1 for better compatibility
          sampleRate: Platform.isIOS ? 44100 : 16000,
          // sampleRate: 48000,
          interleaved: true,
          bufferSize: 2048, // Increased buffer size for stability
        );

        _isPlayerReady = true;
        print("🎵 [CLIENT] Player initialized for streaming");
      } catch (e) {
        print("❌ [CLIENT] Error initializing stream player: $e");
        _isPlayerReady = false;

        // // Reset and retry
        // await _resetAudioPlayer();
        // await _startPlayerForStream();
      }
    }
  }

  // Future<void> _resetAudioPlayer() async {
  //   try {
  //     await _audioPlayer?.stopPlayer();
  //     await _audioPlayer?.closePlayer();
  //     _audioPlayer = FlutterSoundPlayer();
  //     await _audioPlayer?.openPlayer();
  //     _isPlayerReady = false;
  //   } catch (e) {
  //     print("❌ [AUDIO] Error resetting audio player: $e");
  //   }
  // }

  Future<void> _stopPlayerForStream() async {
    try {
      if (_isPlayerReady) {
        await _audioPlayer?.stopPlayer();

        // // Check if player is actually playing before stopping
        // if (!(_audioPlayer?.isStopped ?? true)) {
        //   await _audioPlayer?.stopPlayer();
        // }
        _isPlayerReady = false;
        print("🛑 [CLIENT] Player stopped");
      }
    } catch (e) {
      print("❌ [CLIENT] Error stopping player: $e");
      // Force reset on error
      // await _resetAudioPlayer();
    }
  }

  // Updated Real-Time Streaming Methods
  // Real-Time Streaming Methods
  void _startStreaming() async {
    if (_isStreaming || _isRecording) return;
    setState(() => _isStreaming = true);

    _audioStreamController = StreamController<Uint8List>();
    _audioStreamController?.stream.listen(_sendStreamedAudio);

    await _audioRecorder?.startRecorder(
      codec: Codec.pcm16,
      numChannels: 1,
      // sampleRate: 48000,
      sampleRate: Platform.isIOS ? 44100 : 16000,
      bitRate: 16000,
      // bufferSize: 1024, // 8192
      bufferSize: 2048,
      toStream: _audioStreamController?.sink,
    );
  }

  void _stopStreaming() async {
    if (!_isStreaming) return;

    try {
      setState(() => _isStreaming = false);

      // Stop recorder first
      await _audioRecorder!.stopRecorder();

      // Close stream controller
      await _audioStreamController?.close();
      _audioStreamController = null;

      // Send stop signal to receivers
      // Send stop signal
      Uint8List stopSignal = Uint8List.fromList([0xFF, 0xFF, 0xFF, 0xFF]);
      for (String ip in connectedUsers) {
        if (ip != _myIpAddress) {
          UDP sender = await UDP.bind(Endpoint.any());
          await sender.send(
            stopSignal,
            Endpoint.unicast(InternetAddress(ip), port: Port(6006)),
          );
          sender.close();
        }
      }
      print("🛑 [AUDIO] Stopped streaming successfully");
    } catch (e) {
      print("❌ [AUDIO] Error stopping stream: $e");
    }
  }

  void _sendStreamedAudio(Uint8List audioChunk) async {
    if (audioChunk.isEmpty) return;
    List<Uint8List> bufferUint8 = [];
    bufferUint8.add(audioChunk);

    // ✅ ensure frame size aligned (16-bit PCM = 2 bytes/sample)
    if (audioChunk.length % 2 != 0) {
      print("⚠️ Skipping misaligned audio chunk size: ${audioChunk.length}");
      return;
    }

    print("📤 Sending audio chunk size: ${audioChunk.length}");

    for (String ip in connectedUsers) {
      if (ip != _myIpAddress) {
        UDP sender = await UDP.bind(Endpoint.any());
        await sender.send(
          audioChunk,
          Endpoint.unicast(InternetAddress(ip), port: Port(6006)),
        );
        sender.close();
      }
    }
  }

  void _listenForStreamedAudio() async {
    try {
      UDP receiver = await UDP.bind(Endpoint.any(port: Port(6006)));
      print("🔄 [CLIENT] Listening for streamed audio on port 6006...");

      receiver.asStream().listen(
        (datagram) async {
          if (datagram != null && datagram.data.isNotEmpty) {
            Uint8List audioData = datagram.data;

            // // Validate data before processing
            // if (audioData.length % 2 != 0) {
            //   print(
            //     "⚠️ Skipping misaligned audio chunk: ${audioData.length} bytes",
            //   );
            //   return;
            // }

            // Check for stop signal
            if (audioData.length == 4 &&
                audioData[0] == 0xFF &&
                audioData[1] == 0xFF &&
                audioData[2] == 0xFF &&
                audioData[3] == 0xFF) {
              print("🛑 [AUDIO] Received stop signal");
              _silenceTimer?.cancel();
              return;
            }

            // Ensure player is ready before feeding data
            await _startPlayerForStream();

            // // Reset silence timer
            // _silenceTimer?.cancel();
            // _silenceTimer = Timer(Duration(milliseconds: 500), () async {
            //   await _stopPlayerForStream();
            //   print("🔇 [CLIENT] No audio for 500ms, stopping player...");
            // });

            // print("📥 Received audio chunk size: ${audioData.length}");

            // await _audioPlayer!.feedUint8FromStream(audioData);

            // Process audio data with enhanced error handling
            await _processAudioData(audioData);
          }
        },
        onError: (error) {
          print("❌ [AUDIO] UDP reception error: $error");
        },
        cancelOnError: true,
      );
    } catch (e) {
      print("❌ [AUDIO] Error binding UDP socket: $e");

      // Retry binding after delay
      if (mounted) {
        Future.delayed(Duration(seconds: 2), () {
          if (!_isDisposed) {
            _listenForStreamedAudio();
          }
        });
      }
    }
  }

  // Improved audio data processing
  Future<void> _processAudioData(Uint8List audioData) async {
    if (_isDisposed) return;

    try {
      // Validate audio data
      if (audioData.isEmpty || audioData.length % 2 != 0) {
        print("⚠️ [AUDIO] Invalid audio data received, skipping");
        return;
      }

      // Ensure player is ready
      if (!_isPlayerReady) {
        await _initAudio();
        if (!_isPlayerReady) {
          print("❌ [AUDIO] Player not ready, cannot process audio");
          return;
        }
      }

      // Cancel previous silence timer
      _silenceTimer?.cancel();

      // Feed audio data to player
      await _audioPlayer!.feedUint8FromStream(audioData);

      // Set up new silence timer
      _silenceTimer = Timer(Duration(milliseconds: 800), () async {
        if (!_isStreaming && _isPlayerReady) {
          print(
            "🔇 [AUDIO] Silence detected, keeping player alive for potential next stream",
          );
          // Don't stop the player completely, just log the silence
        }
      });
    } catch (e) {
      print("❌ [AUDIO] Error processing audio data: $e");
      // Try to reinitialize player on error
      if (e.toString().contains("stop") || e.toString().contains("closed")) {
        _isPlayerReady = false;
        await _initAudio();
      }
    }
  }

  void _listenForAudio() async {
    UDP receiver = await UDP.bind(Endpoint.any(port: Port(6005)));
    print("🔄 [CLIENT] Listening for audio on port 6005...");

    receiver.asStream().listen((datagram) async {
      if (datagram != null && datagram.data.isNotEmpty) {
        Uint8List audioData = datagram.data;
        await _playAudio(audioData);
      }
    });
  }

  Future<void> _playAudio(Uint8List audioData) async {
    String tempPath = '${Directory.systemTemp.path}/audio.aac';
    await File(tempPath).writeAsBytes(audioData);
    await _audioPlayer?.startPlayer(fromURI: tempPath, codec: Codec.aacADTS);
  }

  void _startRecording() async {
    if (_isRecording) return;

    setState(() {
      _isRecording = true;
    });

    String fileName = 'voice_${DateTime.now().millisecondsSinceEpoch}.aac';
    String filePath = '${await _getVoiceRecordingsDirectory()}/$fileName';

    await _audioRecorder?.startRecorder(toFile: filePath, codec: Codec.aacADTS);

    _audioRecorder?.onProgress?.listen((RecordingDisposition disposition) {
      // Handle recording progress if needed
    });
  }

  void _stopRecording() async {
    if (!_isRecording) return;

    setState(() {
      _isRecording = false;
    });

    String? path = await _audioRecorder?.stopRecorder();
    if (path != null) {
      // Add to local recordings
      VoiceRecording recording = VoiceRecording(
        filePath: path,
        fileName: path.split('/').last,
        timestamp: DateTime.now(),
        duration: 0, // Calculate actual duration if needed
        senderIp: _myIpAddress,
      );

      setState(() {
        _voiceRecordings.insert(0, recording);
      });

      await _saveVoiceRecordingMetadata();

      // Send to other users
      Uint8List audioData = await File(path).readAsBytes();
      _sendAudioData(audioData);

      // Also send as voice recording file for history
      await _sendVoiceRecording(path);
    }
  }

  void _sendAudioData(Uint8List audioData) async {
    for (String ip in connectedUsers) {
      if (ip != _myIpAddress) {
        // Skip your own IP
        UDP sender = await UDP.bind(Endpoint.any());
        await sender.send(
          audioData,
          Endpoint.unicast(InternetAddress(ip), port: Port(6005)),
        );
        sender.close();
      }
    }
  }

  void _startReceivingRequests() async {
    udpSocket = await UDP.bind(
      Endpoint.any(port: Port(6002)),
    ); // Host listens on 6002
    print("🔵 [HOST] Listening for join requests on port 6002...");

    // Add the host itself to the list
    String hostIp = widget.hostIp;
    _addUser(hostIp);

    udpSocket?.asStream().listen((datagram) async {
      if (datagram != null) {
        String message = String.fromCharCodes(datagram.data);
        String userIp = datagram.address.address;

        if (message == "MotoVox_DISCOVER") {
          print(
            "📡 [HOST] Discovery request received from $userIp, responding...",
          );

          UDP sender = await UDP.bind(Endpoint.any());
          await sender.send(
            hostIp.codeUnits,
            Endpoint.unicast(
              InternetAddress(userIp),
              port: Port(discoveryPort),
            ),
          );
          sender.close();
        } else if (message == "JOIN") {
          print("✅ [HOST] Join request received from: $userIp");

          _addUser(userIp);
          _broadcastUserList();

          // ✅ Send confirmation to new client
          UDP sender = await UDP.bind(Endpoint.any());
          await sender.send(
            "JOINED".codeUnits,
            Endpoint.unicast(InternetAddress(userIp), port: Port(6003)),
          );
          sender.close();
        } else if (message == "LEAVE") {
          print("🚪 [HOST] Leave request received from: $userIp");
          _removeUser(userIp);
          _broadcastUserList();
        } else if (message == "PING") {
          // Respond to ping from clients
          UDP sender = await UDP.bind(Endpoint.any());
          await sender.send(
            Uint8List.fromList("PONG".codeUnits),
            Endpoint.unicast(InternetAddress(userIp), port: Port(6010)),
          );
          sender.close();
        }
      }
    });
  }

  void _addUser(String userIp) {
    if (!connectedUsers.contains(userIp)) {
      _connectedUsersNotifier.value = [...connectedUsers, userIp];
      print("➕ [USERS] User added: $userIp, Total: ${connectedUsers.length}");
    }
  }

  void _removeUser(String userIp) {
    if (connectedUsers.contains(userIp)) {
      _connectedUsersNotifier.value = connectedUsers
          .where((ip) => ip != userIp)
          .toList();
      print("➖ [USERS] User removed: $userIp, Total: ${connectedUsers.length}");
    }
  }

  void _sendJoinRequest() async {
    print(
      "📩 [CLIENT] Sending join request to: ${widget.hostIp}:6002",
    ); // Debug log

    if (widget.hostIp.isEmpty) {
      print("❌ Invalid Host IP");
      return;
    }

    UDP sender = await UDP.bind(Endpoint.any());
    for (int i = 0; i < 3; i++) {
      await sender.send(
        Uint8List.fromList("JOIN".codeUnits),
        Endpoint.unicast(InternetAddress(widget.hostIp), port: Port(6002)),
      );
      await Future.delayed(Duration(milliseconds: 500));
    }
    sender.close();
    print("📩 [CLIENT] Join request sent to ${widget.hostIp}");
  }

  void _broadcastUserList() async {
    if (connectedUsers.isEmpty) return;

    String userList = connectedUsers.join(',');
    Uint8List data = Uint8List.fromList(userList.codeUnits);

    print("📢 [HOST] Sending updated user list: $userList");

    for (String ip in connectedUsers) {
      UDP sender = await UDP.bind(Endpoint.any());
      await sender.send(
        data,
        Endpoint.unicast(InternetAddress(ip), port: Port(6003)),
      );
      sender.close();
    }
  }

  void _listenForUpdates() async {
    UDP receiver = await UDP.bind(Endpoint.any(port: Port(6003)));
    log("🔄 [CLIENT] Listening for user list updates on port 6003...");

    receiver.asStream().listen(
      (datagram) {
        if (datagram != null && datagram.data.isNotEmpty) {
          String receivedData = String.fromCharCodes(datagram.data);

          if (receivedData == "HOST_LEAVING") {
            _handleHostDisconnected();
            return;
          }

          List<String> updatedUsers = receivedData.split(',');
          log("receivedData $receivedData");

          if (receivedData.contains(',') ||
              RegExp(r'^(\d{1,3}\.){3}\d{1,3}$').hasMatch(receivedData)) {
            List<String> updatedUsers = receivedData.split(',');
            log("🔄 [CLIENT] Received updated user list: $updatedUsers");

            _connectedUsersNotifier.value = updatedUsers;
          }

          log("🔄 [CLIENT] State updated with: $connectedUsers");
        }
      },
      onError: (error) {
        log("❌ [CLIENT] Error receiving user list updates: $error");
      },
    );
  }

  void _sendMessage(String message) async {
    if (message.trim().isEmpty) return;

    Uint8List data = Uint8List.fromList(message.codeUnits);
    log("📢 Sending message: $message");

    // Ensure message is sent to all users, including the host
    for (String ip in connectedUsers) {
      UDP sender = await UDP.bind(Endpoint.any());
      await sender.send(
        data,
        Endpoint.unicast(InternetAddress(ip), port: Port(6004)),
      );
      sender.close();
    }

    messageController.clear();
  }

  void _listenForMessages() async {
    UDP receiver = await UDP.bind(Endpoint.any(port: Port(6004)));
    print("🔄 [CLIENT] Listening for messages on port 6004...");

    receiver.asStream().listen((datagram) {
      if (datagram != null && datagram.data.isNotEmpty) {
        String receivedMessage = String.fromCharCodes(datagram.data);
        print("💬 New message received: $receivedMessage");

        setState(() {
          messages.add(receivedMessage);
        });
      }
    });
  }

  // TCP Server for reliable file transfer
  void _startTcpServer() async {
    try {
      _tcpServer = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        TCP_FILE_PORT,
      );
      log(
        "sendvideo _startTcpServer 🚀 [HOST] TCP File Server started on port $TCP_FILE_PORT",
      );

      _tcpServer?.listen((Socket client) {
        log(
          "sendvideo _startTcpServer 📁 [HOST] New TCP client connected: ${client.remoteAddress.address}",
        );
        _tcpClients.add(client);

        // Listen for incoming files
        _handleIncomingFiles(client);

        client.done.then((_) {
          _tcpClients.remove(client);
          log("sendvideo _startTcpServer 📁 [HOST] TCP client disconnected");
        });
      });
    } catch (e) {
      log("sendvideo _startTcpServer ❌ [HOST] Error starting TCP server: $e");
    }
  }

  void _handleIncomingFiles(Socket client) {
    List<int> fileBuffer = [];
    int? fileSize;
    int receivedBytes = 0;
    String? fileName;

    client.listen(
      (List<int> data) {
        try {
          // First packet contains file info
          if (fileSize == null) {
            // Parse header: [fileSize:4bytes][fileNameLength:4bytes][fileName]
            ByteData headerData = ByteData.sublistView(
              Uint8List.fromList(data.sublist(0, 8)),
            );
            fileSize = headerData.getUint32(0, Endian.big);
            int nameLength = headerData.getUint32(4, Endian.big);
            fileName = String.fromCharCodes(data.sublist(8, 8 + nameLength));

            log(
              "sendvideo _handleIncomingFiles 📥 [HOST] Receiving file: $fileName, Size: $fileSize bytes",
            );

            // Add the remaining data to buffer
            fileBuffer.addAll(data.sublist(8 + nameLength));
            receivedBytes = fileBuffer.length;
          } else {
            fileBuffer.addAll(data);
            receivedBytes += data.length;
          }

          // Show progress
          double progress = (receivedBytes / fileSize!) * 100;
          log(
            "sendvideo _handleIncomingFiles 📥 [HOST] File progress: ${progress.toStringAsFixed(1)}%",
          );

          // File complete
          if (receivedBytes >= fileSize!) {
            _saveReceivedFile(Uint8List.fromList(fileBuffer), fileName!);
            fileBuffer.clear();
            fileSize = null;
            receivedBytes = 0;
            fileName = null;
          }
        } catch (e) {
          log(
            "sendvideo _handleIncomingFiles ❌ [HOST] Error processing file data: $e",
          );
        }
      },
      onError: (error) {
        log("sendvideo _handleIncomingFiles ❌ [HOST] TCP client error: $error");
        _tcpClients.remove(client);
      },
    );
  }

  // TCP Client connection for non-host clients
  void _connectToTcpServer() async {
    if (widget.isHost) return; // Host doesn't need to connect to itself

    try {
      Socket client = await Socket.connect(widget.hostIp, TCP_FILE_PORT);
      _tcpClients.add(client);
      log(
        "sendvideo _connectToTcpServer 🔗 [CLIENT] Connected to TCP server at ${widget.hostIp}:$TCP_FILE_PORT",
      );

      // Listen for incoming files from host
      _handleIncomingFiles(client);
    } catch (e) {
      log(
        "sendvideo _connectToTcpServer ❌ [CLIENT] Error connecting to TCP server: $e",
      );
    }
  }

  // Send video file over TCP (Reliable)
  Future<void> _sendVideoFileOverTCP(XFile videoFile) async {
    if (_tcpClients.isEmpty) {
      log("sendvideo ❌ No TCP connections available");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No TCP connections available'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isSendingFile = true;
      _fileTransferProgress = 0.0;
      _currentFileName = videoFile.name;
    });

    _showFileTransferProgressDialog();

    Timer? progressTimer;
    int totalBytes = 0;
    int bytesSent = 0;

    try {
      Uint8List videoData = await videoFile.readAsBytes();
      totalBytes = videoData.length;
      String fileName = 'video_${DateTime.now().millisecondsSinceEpoch}.mp4';

      // Start progress timer (updates every 100ms for smooth animation)
      progressTimer = Timer.periodic(Duration(milliseconds: 100), (timer) {
        if (bytesSent >= totalBytes) {
          timer.cancel();
          _progressController?.add(1.0);
        } else {
          double progress = bytesSent / totalBytes;
          _progressController?.add(progress);
        }
      });

      // Create header
      Uint8List fileNameBytes = Uint8List.fromList(fileName.codeUnits);
      Uint8List header = Uint8List(8 + fileNameBytes.length);
      ByteData headerData = ByteData.view(header.buffer);
      headerData.setUint32(0, videoData.length, Endian.big);
      headerData.setUint32(4, fileNameBytes.length, Endian.big);
      header.setRange(8, 8 + fileNameBytes.length, fileNameBytes);

      List<Socket> clients = List.from(_tcpClients);
      int successfulSends = 0;

      for (Socket client in clients) {
        try {
          client.remoteAddress; // Connection check

          // Send header and entire file data at once for maximum speed
          client.add(header);
          client.add(videoData);
          await client.flush();

          bytesSent = totalBytes; // Mark as complete for this client
          successfulSends++;

          log("sendvideo 📤 [TCP] Video file sent to client: $fileName");
        } catch (e) {
          log("sendvideo ❌ [TCP] Client error, removing: $e");
          _tcpClients.remove(client);
        }
      }

      await Future.delayed(Duration(milliseconds: 500)); // Show completion

      log(
        "sendvideo 📤 [TCP] Video file sent: $fileName (${videoData.length} bytes) to $successfulSends clients",
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Video sent to $successfulSends client(s)'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      log("sendvideo ❌ [TCP] Error sending video file: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sending video file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      progressTimer?.cancel();
      setState(() {
        _isSendingFile = false;
      });
      _hideFileTransferProgressDialog();
    }
  }

  // Save received file
  Future<void> _saveReceivedFile(Uint8List fileData, String fileName) async {
    try {
      String directory = await _getAppDirectory();
      String filePath = '$directory/$fileName';

      await File(filePath).writeAsBytes(fileData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('File received: $fileName'),
            backgroundColor: Colors.green,
          ),
        );
      }

      log("sendvideo _saveReceivedFile 💾 File saved: $filePath");
      if (filePath != null) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Text('Video Received'),
              content: Text('Video saved to: $filePath'),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (context) =>
                          VideoPathDialog(videoPath: filePath),
                    );
                  },
                  child: Text('OK'),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      log("sendvideo _saveReceivedFile  ❌ Error saving file: $e");
    }
  }

  Future<String> _getAppDirectory() async {
    final directory = Directory.systemTemp;
    return directory.path;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        if (widget.isHost) {
          final shouldExit =
              await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text("Exit Lobby?"),
                  content: const Text(
                    "You are the host. If you leave, all clients will be disconnected. Are you sure?",
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text("Cancel"),
                    ),
                    TextButton(
                      onPressed: () async {
                        await _cleanupAndLeave();

                        Navigator.of(context).pop(true);
                      },
                      child: const Text("Exit"),
                    ),
                  ],
                ),
              ) ??
              false;

          if (shouldExit) {
            for (String ip in connectedUsers) {
              if (ip != _myIpAddress) {
                try {
                  final sender = await UDP.bind(Endpoint.any());
                  await sender.send(
                    Uint8List.fromList("HOST_LEAVING".codeUnits),
                    Endpoint.unicast(InternetAddress(ip), port: Port(6003)),
                  );
                  sender.close();
                } catch (e) {
                  print("❌ Error notifying client $ip: $e");
                }
              }
            }

            await _cleanupAndLeave();
            if (context.mounted) Navigator.of(context).pop(result);
          }
        } else {
          await _cleanupAndLeave();
          if (context.mounted) Navigator.of(context).pop(result);
        }
      },
      child: SafeArea(
        child: Scaffold(
          extendBodyBehindAppBar: true,
          body: SingleChildScrollView(
            child: GestureDetector(
              onTap: () {
                FocusManager.instance.primaryFocus?.unfocus();
              },
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFFF6767), Color(0xFF11E0DC)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height,
                  width: MediaQuery.of(context).size.width,
                  child: Column(
                    children: [
                      // Header Section
                      Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 8,
                        ),
                        child: Column(
                          children: [
                            Text(
                              "Connected Users",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 8),
                            ValueListenableBuilder<List<String>>(
                              valueListenable: _connectedUsersNotifier,
                              builder: (context, users, child) {
                                if (users.isEmpty) {
                                  return Padding(
                                    padding: EdgeInsets.all(8.0),
                                    child: Text(
                                      "No users connected yet",
                                      style: TextStyle(
                                        color: Colors.grey,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                  );
                                } else {
                                  return ListView.builder(
                                    shrinkWrap: true,
                                    physics: AlwaysScrollableScrollPhysics(),
                                    itemCount: users.length,

                                    itemBuilder: (context, index) {
                                      String ip = users[index];
                                      bool isHost = ip == widget.hostIp;
                                      bool isMe = ip == _myIpAddress;

                                      String displayText;
                                      if (isHost && isMe) {
                                        displayText = "You (Host)";
                                      } else if (isHost) {
                                        displayText = "Host";
                                      } else if (isMe) {
                                        displayText = "You";
                                      } else {
                                        displayText = "User";
                                      }

                                      return InkWell(
                                        borderRadius: BorderRadius.circular(12),
                                        onTap: () {
                                          print("Tapped on $ip ($displayText)");
                                          // 👉 Add your custom logic here, e.g.:
                                          // Navigator.push(context, MaterialPageRoute(builder: (_) => UserDetailScreen(ip: ip)));
                                        },
                                        child: Container(
                                          margin: EdgeInsets.symmetric(
                                            vertical: 4,
                                            horizontal: 8,
                                          ),
                                          padding: EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade100,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            border: Border.all(
                                              color: Colors.grey.shade300,
                                              width: 1,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                isHost
                                                    ? Icons.cell_tower
                                                    : Icons.person,
                                                color: isHost
                                                    ? Colors.blue
                                                    : Colors.green,
                                                size: 20,
                                              ),
                                              SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  "$displayText: $ip",
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w500,
                                                    color: Colors.black87,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              if (isMe)
                                                Padding(
                                                  padding: EdgeInsets.only(
                                                    left: 8,
                                                  ),
                                                  child: Icon(
                                                    Icons.circle,
                                                    color: Colors.green,
                                                    size: 8,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                      ),

                      // Messages Section
                      Expanded(
                        child: Container(
                          margin: EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(15),
                              topRight: Radius.circular(15),
                            ),
                          ),
                          child: Column(
                            children: [
                              Container(
                                padding: EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.grey[300],
                                  borderRadius: BorderRadius.only(
                                    topLeft: Radius.circular(15),
                                    topRight: Radius.circular(15),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.chat,
                                      size: 20,
                                      color: Colors.blueGrey,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      "Chat Messages",
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.blueGrey,
                                      ),
                                    ),
                                    Spacer(),
                                    Text(
                                      "(${messages.length})",
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: messages.isEmpty
                                    ? Center(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.chat_bubble_outline,
                                              size: 60,
                                              color: Colors.grey,
                                            ),
                                            SizedBox(height: 8),
                                            Text(
                                              "No messages yet",
                                              style: TextStyle(
                                                color: Colors.grey,
                                                fontSize: 16,
                                              ),
                                            ),
                                            Text(
                                              "Start a conversation!",
                                              style: TextStyle(
                                                color: Colors.grey,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    : Padding(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 8,
                                        ),
                                        child: ListView.builder(
                                          reverse: false,
                                          shrinkWrap: true,
                                          physics:
                                              AlwaysScrollableScrollPhysics(),
                                          itemCount: messages.length,
                                          itemBuilder: (context, index) {
                                            bool isMyMessage = messages[index]
                                                .startsWith("You:");
                                            return Container(
                                              margin: EdgeInsets.symmetric(
                                                vertical: 4,
                                              ),
                                              padding: EdgeInsets.all(10),
                                              decoration: BoxDecoration(
                                                color: isMyMessage
                                                    ? Colors.blue[50]
                                                    : Colors.white,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: isMyMessage
                                                      ? Colors.blue[100]!
                                                      : Colors.grey[300]!,
                                                  width: 1,
                                                ),
                                              ),
                                              child: Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  if (!isMyMessage)
                                                    Icon(
                                                      Icons.person,
                                                      size: 16,
                                                      color: Colors.grey,
                                                    ),
                                                  if (!isMyMessage)
                                                    SizedBox(width: 6),
                                                  Expanded(
                                                    child: Text(
                                                      messages[index],
                                                      style: TextStyle(
                                                        fontSize: 14,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Input Section
                      Container(
                        color: Colors.transparent,
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(25),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: messageController,
                                  decoration: InputDecoration(
                                    hintText: "Type a message...",
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 14,
                                    ),
                                  ),
                                  maxLines: 3,
                                  minLines: 1,
                                ),
                              ),
                              Container(
                                margin: EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.blueAccent,
                                ),
                                child: IconButton(
                                  onPressed: () =>
                                      _sendMessage(messageController.text),
                                  icon: Icon(Icons.send, color: Colors.white),
                                  splashRadius: 20,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Controls Section
                      Container(
                        padding: EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 16,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(20),
                            topRight: Radius.circular(20),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Video Recording Section
                            Column(
                              children: [
                                Text(
                                  "Video Recording",
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                ),
                                SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _buildControlButton(
                                      icon: Icons.video_library,
                                      label: "Videos",
                                      onPressed: _listAllVideos,
                                      color: Colors.blue,
                                    ),
                                    SizedBox(width: 16),
                                    _buildControlButton(
                                      icon: Icons.videocam,
                                      label: "Record",
                                      onPressed: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (context) => BlocProvider(
                                              create: (context) {
                                                return CameraBloc(
                                                  cameraUtils: CameraUtils(),
                                                  permissionUtils:
                                                      PermissionUtils(),
                                                )..add(
                                                  const CameraInitialize(
                                                    recordingLimit: 15,
                                                  ),
                                                );
                                              },
                                              child: CameraPage(
                                                onVideoRecorded:
                                                    (String videoPath) async {
                                                      print(
                                                        'sendvideo Video recorded at: $videoPath',
                                                      );
                                                      XFile xFile = XFile(
                                                        videoPath,
                                                      );
                                                      await _sendVideoFileOverTCP(
                                                        xFile,
                                                      );
                                                    },
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                      color: Colors.red,
                                    ),
                                    SizedBox(width: 16),

                                    _buildControlButton(
                                      icon: Icons.video_call_outlined,
                                      label: "Video Call",
                                      onPressed: () {
                                        // Navigator.of(context).push(
                                        //   MaterialPageRoute(
                                        //     builder: (context) => BlocProvider(
                                        //       create: (context) {
                                        //         return CameraBloc(
                                        //           cameraUtils: CameraUtils(),
                                        //           permissionUtils:
                                        //               PermissionUtils(),
                                        //         )..add(
                                        //           const CameraInitialize(
                                        //             recordingLimit: 15,
                                        //           ),
                                        //         );
                                        //       },
                                        //       child: CameraPage(
                                        //         onVideoRecorded:
                                        //             (String videoPath) async {
                                        //               print(
                                        //                 'sendvideo Video recorded at: $videoPath',
                                        //               );
                                        //               XFile xFile = XFile(
                                        //                 videoPath,
                                        //               );
                                        //               await _sendVideoFileOverTCP(
                                        //                 xFile,
                                        //               );
                                        //             },
                                        //       ),
                                        //     ),
                                        //   ),
                                        // );
                                      },
                                      color: Colors.red,
                                    ),
                                  ],
                                ),
                              ],
                            ),

                            SizedBox(height: 16),

                            // Voice Controls Section - UPDATED
                            Column(
                              children: [
                                Text(
                                  "Voice Messages",
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                ),
                                SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    // Voice Recordings History Button
                                    _buildControlButton(
                                      icon: Icons.audio_file,
                                      label: "History",
                                      onPressed: _listAllVoiceRecordings,
                                      color: Colors.purple,
                                    ),
                                    SizedBox(width: 16),
                                    // Recording Button
                                    _buildControlButton(
                                      icon: _isRecording
                                          ? Icons.stop
                                          : Icons.mic,
                                      label: _isRecording ? "Stop" : "Record",
                                      onPressed: () async {
                                        if (_isRecording) {
                                          _stopRecording();
                                        } else {
                                          if (await PermissionUtils()
                                              .getCameraAndMicrophonePermissionStatus()) {
                                            _startRecording();
                                          } else {
                                            if (await PermissionUtils()
                                                .askForPermission()) {
                                              _startRecording();
                                            } else {
                                              log("Permission is denied");
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    'Microphone permission required',
                                                  ),
                                                  backgroundColor: Colors.red,
                                                ),
                                              );
                                            }
                                          }
                                        }
                                      },
                                      color: _isRecording
                                          ? Colors.red
                                          : Colors.blue,
                                      isActive: _isRecording,
                                    ),
                                    SizedBox(width: 16),
                                    // Push-to-Talk Button
                                    _buildControlButton(
                                      icon: _isStreaming
                                          ? Icons.cancel
                                          : Icons.record_voice_over,
                                      label: _isStreaming ? "Stop" : "Talk",
                                      onPressed: () async {
                                        if (_isStreaming) {
                                          _stopStreaming();
                                        } else {
                                          if (await PermissionUtils()
                                              .getCameraAndMicrophonePermissionStatus()) {
                                            _startStreaming();
                                          } else {
                                            if (await PermissionUtils()
                                                .askForPermission()) {
                                              _startStreaming();
                                            } else {
                                              log("Permission is denied");
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    'Microphone permission required',
                                                  ),
                                                  backgroundColor: Colors.red,
                                                ),
                                              );
                                            }
                                          }
                                        }
                                      },
                                      color: _isStreaming
                                          ? Colors.orange
                                          : Colors.green,
                                      isActive: _isStreaming,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Helper method to build control buttons
  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required Color color,
    bool isActive = false,
  }) {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? color.withOpacity(0.2) : Colors.grey[200],
            border: Border.all(
              color: isActive ? color : Colors.transparent,
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: IconButton(
            onPressed: onPressed,
            icon: Icon(icon, size: 28, color: color),
            tooltip: label,
            style: IconButton.styleFrom(
              backgroundColor: Colors.transparent,
              padding: EdgeInsets.all(16),
            ),
          ),
        ),
        SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    // Clean up playback resources
    _stopVoicePlayback();
    _playbackTimer?.cancel();
    _playbackSubscription?.cancel();

    // _keepAliveTimer?.cancel();
    _cleanupAndLeave(); // Use the cleanup method

    // udpSocket?.close();
    // _audioRecorder?.closeRecorder();
    // _audioPlayer?.closePlayer();
    // _audioStreamController?.close();
    // _progressController?.close();
    // _connectedUsersNotifier.dispose();

    // for (Socket client in _tcpClients) {
    //   client.destroy();
    // }
    // _tcpServer?.close();
    super.dispose();
  }

  // Load voice recordings from storage
  Future<void> _loadVoiceRecordings() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final voiceDir = Directory('${directory.path}/voice_recordings');

      if (await voiceDir.exists()) {
        List<FileSystemEntity> files = voiceDir.listSync();
        files.sort(
          (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
        );

        List<VoiceRecording> recordings = [];
        for (var file in files) {
          if (file.path.toLowerCase().endsWith('.aac') ||
              file.path.toLowerCase().endsWith('.m4a')) {
            String fileName = file.path.split('/').last;
            DateTime timestamp = (await file.stat()).modified;

            recordings.add(
              VoiceRecording(
                filePath: file.path,
                fileName: fileName,
                timestamp: timestamp,
                duration: 0, // You might want to calculate this
                senderIp: _myIpAddress,
              ),
            );
          }
        }

        setState(() {
          _voiceRecordings = recordings;
        });
      }
    } catch (e) {
      print("❌ Error loading voice recordings: $e");
    }
  }

  // Save voice recording metadata
  Future<void> _saveVoiceRecordingMetadata() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final metadataFile = File(
        '${directory.path}/voice_recordings_metadata.json',
      );

      List<Map<String, dynamic>> recordingsJson = _voiceRecordings
          .map((recording) => recording.toJson())
          .toList();

      await metadataFile.writeAsString(json.encode(recordingsJson));
    } catch (e) {
      print("❌ Error saving voice recording metadata: $e");
    }
  }

  // Get voice recordings directory
  Future<String> _getVoiceRecordingsDirectory() async {
    final directory = await getApplicationDocumentsDirectory();
    final voiceDir = Directory('${directory.path}/voice_recordings');

    if (!await voiceDir.exists()) {
      await voiceDir.create(recursive: true);
    }

    return voiceDir.path;
  }

  // Listen for incoming voice recordings
  void _listenForVoiceRecordings() async {
    UDP receiver = await UDP.bind(Endpoint.any(port: Port(VOICE_PORT)));
    print("🎵 [VOICE] Listening for voice recordings on port $VOICE_PORT...");

    receiver.asStream().listen((datagram) async {
      if (datagram != null && datagram.data.isNotEmpty) {
        String senderIp = datagram.address.address;
        Uint8List data = datagram.data;

        try {
          // Check if this is a voice recording file
          if (data.length > 100) {
            // Assuming voice files are larger than 100 bytes
            await _saveReceivedVoiceRecording(data, senderIp);
          }
        } catch (e) {
          print("❌ Error processing voice recording from $senderIp: $e");
        }
      }
    });
  }

  // Save received voice recording
  Future<void> _saveReceivedVoiceRecording(
    Uint8List audioData,
    String senderIp,
  ) async {
    try {
      final voiceDir = await _getVoiceRecordingsDirectory();
      String fileName =
          'voice_${DateTime.now().millisecondsSinceEpoch}_from_${senderIp.replaceAll('.', '_')}.aac';
      String filePath = '$voiceDir/$fileName';

      await File(filePath).writeAsBytes(audioData);

      VoiceRecording recording = VoiceRecording(
        filePath: filePath,
        fileName: fileName,
        timestamp: DateTime.now(),
        duration: 0, // You might want to calculate actual duration
        senderIp: senderIp,
      );

      setState(() {
        _voiceRecordings.insert(
          0,
          recording,
        ); // Add to beginning for newest first
      });

      await _saveVoiceRecordingMetadata();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Voice message received from ${senderIp == _myIpAddress ? 'You' : senderIp}',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }

      print("🎵 Voice recording saved: $filePath");
    } catch (e) {
      print("❌ Error saving voice recording: $e");
    }
  }

  // Send voice recording to all users
  Future<void> _sendVoiceRecording(String filePath) async {
    try {
      Uint8List audioData = await File(filePath).readAsBytes();

      for (String ip in connectedUsers) {
        if (ip != _myIpAddress) {
          UDP sender = await UDP.bind(Endpoint.any());
          await sender.send(
            audioData,
            Endpoint.unicast(InternetAddress(ip), port: Port(VOICE_PORT)),
          );
          sender.close();
        }
      }

      print("🎵 Voice recording sent to ${connectedUsers.length - 1} users");
    } catch (e) {
      print("❌ Error sending voice recording: $e");
    }
  }

  // List all voice recordings
  Future<void> _listAllVoiceRecordings() async {
    try {
      if (_voiceRecordings.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('No voice recordings found')));
        }
        return;
      }

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Voice Recordings (${_voiceRecordings.length})'),
          content: Container(
            width: double.maxFinite,
            height: MediaQuery.of(context).size.height * 0.6,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _voiceRecordings.length,
              itemBuilder: (context, index) {
                VoiceRecording recording = _voiceRecordings[index];
                bool isMyRecording = recording.senderIp == _myIpAddress;

                return Container(
                  margin: EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: isMyRecording ? Colors.blue[50] : Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isMyRecording
                          ? Colors.blue[100]!
                          : Colors.grey[300]!,
                    ),
                  ),
                  child: ListTile(
                    leading: Icon(
                      Icons.audiotrack,
                      color: isMyRecording ? Colors.blue : Colors.green,
                    ),
                    title: Text(
                      'Voice Message',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'From: ${isMyRecording ? 'You' : recording.senderIp}',
                          style: TextStyle(fontSize: 12),
                        ),
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
                            // _playVoiceRecording(recording);
                            // showDialog(
                            //   context: context,
                            //   builder: (context) => AudioDialogExample(
                            //     audioPath:
                            //         recording.filePath, // or a local file path
                            //   ),
                            // );

                            showDialog(
                              context: context,
                              builder: (context) => ModernAudioDialog(
                                filePath: recording.filePath,
                                sender: recording.senderIp,
                                timestamp: DateTime.now(),
                                isMyRecording: isMyRecording,
                              ),
                            );
                          },
                        ),
                        IconButton(
                          icon: Icon(Icons.delete, color: Colors.red),
                          onPressed: () =>
                              _deleteVoiceRecording(recording, index),
                        ),
                      ],
                    ),
                  ),
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
        ),
      );
    } catch (e) {
      print("❌ Error listing voice recordings: $e");
    }
  }

  // Play voice recording with dialog
  // Play voice recording with dialog
  Future<void> _playVoiceRecording(VoiceRecording recording) async {
    try {
      setState(() {
        _currentlyPlayingRecording = recording;
        _isPlayingVoice = true;
        _playbackPosition = 0.0;
        _playbackDuration = 0.0;
      });

      // Open player if not yet
      await _audioPlayer?.openPlayer();
      _audioPlayer?.setSubscriptionDuration(const Duration(milliseconds: 500));

      // Start playback
      await _audioPlayer?.startPlayer(
        fromURI: recording.filePath,
        codec: Codec.aacADTS,
        whenFinished: () {
          if (mounted) {
            setState(() {
              _isPlayingVoice = false;
              _playbackPosition = 0.0;
            });
            Navigator.of(context, rootNavigator: true).pop(); // close dialog
          }
        },
      );

      // Show playing dialog (after start)
      _showVoicePlayingDialog(recording);
    } catch (e) {
      print("❌ Error playing voice recording: $e");
      _stopVoicePlayback();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error playing voice message'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Stop voice playback
  Future<void> _stopVoicePlayback() async {
    await _audioPlayer?.stopPlayer();
    await _playbackSubscription?.cancel();

    if (mounted) {
      Navigator.of(context, rootNavigator: true).maybePop();
      setState(() {
        _isPlayingVoice = false;
        _currentlyPlayingRecording = null;
        _playbackPosition = 0.0;
        _playbackDuration = 0.0;
      });
    }
  }

  // Pause/Resume playback
  Future<void> _pauseResumeVoicePlayback() async {
    if (_isPlayingVoice) {
      await _audioPlayer?.pausePlayer();
    } else {
      await _audioPlayer?.resumePlayer();
    }
    if (mounted) {
      setState(() => _isPlayingVoice = !_isPlayingVoice);
    }
  }

  // Show voice playing dialog
  void _showVoicePlayingDialog(VoiceRecording recording) {
    _playbackSubscription = _audioPlayer?.onProgress?.listen((event) {
      if (!mounted) return;
      setState(() {
        _playbackPosition = event.position.inMilliseconds.toDouble();
        _playbackDuration = event.duration.inMilliseconds.toDouble();
      });
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            double progress = _playbackDuration > 0
                ? (_playbackPosition / _playbackDuration).clamp(0.0, 1.0)
                : 0.0;

            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      children: [
                        const Icon(Icons.audiotrack, color: Colors.blue),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "Playing Voice Message",
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Sender info
                    Text(
                      'From: ${recording.senderIp == _myIpAddress ? 'You' : recording.senderIp}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatDateTime(recording.timestamp),
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),

                    // Slider and duration
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Slider(
                          value: _playbackPosition.clamp(
                            0.0,
                            _playbackDuration,
                          ),
                          min: 0.0,
                          max: _playbackDuration > 0 ? _playbackDuration : 1.0,
                          activeColor: Colors.blue,
                          inactiveColor: Colors.grey[300],
                          onChanged: (value) async {
                            await _audioPlayer?.seekToPlayer(
                              Duration(milliseconds: value.toInt()),
                            );
                          },
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _formatMilliseconds(_playbackPosition.toInt()),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                            Text(
                              _formatMilliseconds(_playbackDuration.toInt()),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Status text
                    Center(
                      child: Text(
                        _isPlayingVoice ? 'Playing...' : 'Paused',
                        style: TextStyle(
                          fontSize: 14,
                          color: _isPlayingVoice
                              ? Colors.green
                              : Colors.orangeAccent,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Control buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () async => await _stopVoicePlayback(),
                          child: const Text(
                            'Stop',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () async {
                            await _pauseResumeVoicePlayback();
                            setDialogState(() {});
                          },
                          child: Text(
                            _isPlayingVoice ? 'Pause' : 'Resume',
                            style: const TextStyle(color: Colors.blue),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).then((_) => _stopVoicePlayback());
  }

  // Format milliseconds to MM:SS
  String _formatMilliseconds(int milliseconds) {
    int seconds = (milliseconds / 1000).round();
    int minutes = seconds ~/ 60;
    seconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  // Delete voice recording
  void _deleteVoiceRecording(VoiceRecording recording, int index) async {
    try {
      // If currently playing, stop playback first
      if (_currentlyPlayingRecording?.filePath == recording.filePath) {
        _stopVoicePlayback();
      }

      await File(recording.filePath).delete();

      setState(() {
        _voiceRecordings.removeAt(index);
      });

      await _saveVoiceRecordingMetadata();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Voice recording deleted'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print("❌ Error deleting voice recording: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete voice recording'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Format date time for display
  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')} ${dateTime.day}/${dateTime.month}/${dateTime.year}';
  }

  // Show file transfer progress dialog
  void _showFileTransferProgressDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return StreamBuilder<double>(
            stream: _progressController?.stream,
            builder: (context, snapshot) {
              double progress = snapshot.data ?? _fileTransferProgress;

              return AlertDialog(
                title: Row(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'Sending Video File',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _currentFileName,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    // SizedBox(height: 16),
                    // LinearProgressIndicator(
                    //   value: progress,
                    //   backgroundColor: Colors.grey[300],
                    //   valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                    // ),
                    // SizedBox(height: 8),
                    // Text(
                    //   '${(progress * 100).toStringAsFixed(1)}%',
                    //   textAlign: TextAlign.center,
                    //   style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    // ),
                    SizedBox(height: 4),
                    Text(
                      'Sending to ${_tcpClients.length} client(s)',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                    ),
                  ],
                ),
                actions: [
                  if (progress < 1.0)
                    TextButton(
                      onPressed: () {
                        // Option to cancel transfer
                        _isSendingFile = false;
                        Navigator.pop(context);
                      },
                      child: Text('Cancel'),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  // Hide file transfer progress dialog
  void _hideFileTransferProgressDialog() {
    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }
}
