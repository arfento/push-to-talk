import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:push_to_talk_app/views/udp/file_transfer.dart';
import 'package:push_to_talk_app/views/video_stream/widgets/video_dialog.dart';
import 'package:push_to_talk_app/views/video_stream/widgets/video_path_dialog.dart';
import 'package:udp/udp.dart';
import 'package:flutter_sound/flutter_sound.dart';

const int cstSAMPLERATE = 8000;
const int cstCHANNELNB = 2;
const int cstBITRATE = 16000;

class LobbyScreen extends StatefulWidget {
  static const String id = 'lobby_screen';
  final bool isHost;
  final String hostIp; // Host's IP
  final List<CameraDescription> cameras;

  const LobbyScreen({
    required this.isHost,
    required this.hostIp,
    required this.cameras,
  });

  @override
  _LobbyScreenState createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> with WidgetsBindingObserver {
  // final VoiceService voiceService = VoiceService();
  List<String> connectedUsers = []; // Stores connected IPs
  UDP? udpSocket;
  static const int discoveryPort = 5000;
  FlutterSoundRecorder? _audioRecorder;
  FlutterSoundPlayer? _audioPlayer;
  bool _isRecording = false;
  String _myIpAddress = '';
  bool _isStreaming = false; // For real-time streaming
  StreamController<Uint8List>? _audioStreamController; // Added for streaming
  Timer? _silenceTimer; // To detect end of stream on receiver
  bool _isPlayerReady = false; // Track if player is ready for streaming

  // Camera variables
  CameraController? _cameraController;
  bool _isRecordingVideo = false;
  bool _isCameraInitialized = false;
  Timer? _videoChunkTimer;
  List<Uint8List> _videoBuffer = [];
  static const int VIDEO_PORT = 6007;

  @override
  void initState() {
    super.initState();
    // voiceService.init();
    // voiceService.targetIp = widget.hostIp;
    getLocalIp();
    _audioRecorder = FlutterSoundRecorder();
    _audioPlayer = FlutterSoundPlayer();
    _initAudio();

    _initCamera();

    if (widget.isHost) {
      _startReceivingRequests();
    } else {
      _sendJoinRequest();
    }
    _listenForUpdates();
    _listenForMessages();
    _listenForAudio();
    _listenForStreamedAudio(); // New listener for real-time audio
    _listenForVideoStream(); // New listener for video
  }

  Future<String?> getLocalIp() async {
    print("MY IP ADDRESS $_myIpAddress");
    for (var interface in await NetworkInterface.list()) {
      for (var addr in interface.addresses) {
        if (addr.type == InternetAddressType.IPv4 &&
            addr.address.startsWith("172.16.")) {
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

  Future<void> _initAudio() async {
    await _audioRecorder!.openRecorder();
    await _audioPlayer!.openPlayer();
    await _startPlayerForStream(); // Initial setup
  }

  Future<void> _initCamera() async {
    try {
      // Request camera permission
      var status = await Permission.camera.request();
      if (status != PermissionStatus.granted) {
        log('_listenForVideoStream Camera permission denied');
        return;
      }

      if (widget.cameras.isEmpty) {
        log('_listenForVideoStream No cameras available');
        return;
      }

      // Initialize camera controller
      _cameraController = CameraController(
        widget.cameras.first,
        ResolutionPreset.medium,
        enableAudio: true,
      );

      await _cameraController!.initialize();

      setState(() {
        _isCameraInitialized = true;
      });

      log('_listenForVideoStream Camera initialized successfully');
    } catch (e) {
      log('_listenForVideoStream Error initializing camera: $e');
    }
  }

  void _startVideoRecording() async {
    if (!_isCameraInitialized || _isRecordingVideo) return;

    try {
      setState(() {
        _isRecordingVideo = true;
      });

      // Start video recording
      await _cameraController!.startVideoRecording();

      // Start sending video chunks periodically
      _videoChunkTimer = Timer.periodic(Duration(milliseconds: 100), (timer) {
        _captureAndSendVideoFrame();
      });

      log('_listenForVideoStream Started video recording and streaming');
    } catch (e) {
      log('_listenForVideoStream Error starting video recording: $e');
      setState(() {
        _isRecordingVideo = false;
      });
    }
  }

  void _stopVideoRecording() async {
    if (!_isRecordingVideo) return;

    try {
      _videoChunkTimer?.cancel();
      _videoChunkTimer = null;

      // Stop video recording
      final file = await _cameraController!.stopVideoRecording();

      log("_listenForVideoStream _stopVideoRecording $file");

      setState(() {
        _isRecordingVideo = false;
      });

      // Send the complete video file
      await _sendVideoFile(file);

      log('_listenForVideoStream Stopped video recording');
    } catch (e) {
      log('_listenForVideoStream Error stopping video recording: $e');
    }
  }

  Future<void> _captureAndSendVideoFrame() async {
    try {
      if (_cameraController!.value.isStreamingImages && _isRecordingVideo) {
        // Capture a frame (you might need to use a different approach based on your camera package)
        // This is a simplified example - you might need to implement frame capture differently
        XFile? imageFile = await _cameraController!.takePicture();
        if (imageFile != null) {
          Uint8List imageData = await imageFile.readAsBytes();
          _sendVideoChunk(imageData);
        }
      }
    } catch (e) {
      log('_listenForVideoStream Error capturing video frame: $e');
    }
  }

  Future<void> _sendVideoChunk(Uint8List videoData) async {
    if (videoData.isEmpty || connectedUsers.isEmpty) return;

    try {
      for (String ip in connectedUsers) {
        if (ip != _myIpAddress) {
          UDP sender = await UDP.bind(Endpoint.any());
          await sender.send(
            videoData,
            Endpoint.unicast(InternetAddress(ip), port: Port(VIDEO_PORT)),
          );
          sender.close();
        }
      }
    } catch (e) {
      log('_listenForVideoStream Error sending video chunk: $e');
    }
  }

  Future<void> _sendVideoFile(XFile videoFile) async {
    try {
      Uint8List videoData = await videoFile.readAsBytes();
      log(
        '_listenForVideoStream 📤 Sending video file: ${videoData.length} bytes',
      );

      // Use much smaller chunks for UDP reliability
      const int CHUNK_SIZE = 1024; // 1KB chunks - much safer for UDP
      int totalChunks = (videoData.length / CHUNK_SIZE).ceil();

      log(
        '_listenForVideoStream 📦 Dividing into $totalChunks chunks of $CHUNK_SIZE bytes',
      );

      for (int i = 0; i < totalChunks; i++) {
        int start = i * CHUNK_SIZE;
        int end = (i + 1) * CHUNK_SIZE;
        if (end > videoData.length) end = videoData.length;

        Uint8List chunk = videoData.sublist(start, end);

        // Add header with chunk information
        Uint8List header = Uint8List(12);
        ByteData headerData = ByteData.view(header.buffer);
        headerData.setUint32(0, videoData.length);
        headerData.setUint32(4, i);
        headerData.setUint32(8, totalChunks);

        Uint8List packet = Uint8List.fromList([...header, ...chunk]);

        log(
          '_listenForVideoStream 📤 Sending chunk $i/$totalChunks (${packet.length} bytes)',
        );

        // Add retry mechanism for each chunk
        bool sentSuccessfully = false;
        for (int attempt = 0; attempt < 3 && !sentSuccessfully; attempt++) {
          try {
            for (String ip in connectedUsers) {
              if (ip != _myIpAddress) {
                UDP sender = await UDP.bind(Endpoint.any());
                await sender.send(
                  packet,
                  Endpoint.unicast(InternetAddress(ip), port: Port(VIDEO_PORT)),
                );
                sender.close();
              }
            }
            sentSuccessfully = true;
            log('_listenForVideoStream ✅ Chunk $i sent successfully');
          } catch (e) {
            log(
              '_listenForVideoStream ❌ Failed to send chunk $i, attempt ${attempt + 1}/3: $e',
            );
            if (attempt < 2) {
              await Future.delayed(Duration(milliseconds: 100));
            }
          }
        }

        if (!sentSuccessfully) {
          log(
            '_listenForVideoStream 💥 Failed to send chunk $i after 3 attempts',
          );
        }

        // Increase delay to prevent network congestion
        await Future.delayed(Duration(milliseconds: 50));
      }

      log(
        '_listenForVideoStream ✅ Video file sent successfully: ${videoFile.path}',
      );
    } catch (e) {
      log('_listenForVideoStream ❌ Error sending video file: $e');
    }
  }

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

  // Optional: Method for real-time frame display
  void _displayRealTimeVideoFrame(Uint8List frameData, String senderIp) {
    // You can implement real-time video display here
    // This would require a different approach - possibly using a image widget
    // and converting the frame data to an image
    log(
      '_listenForVideoStream 🎬 Real-time frame from $senderIp: ${frameData.length} bytes',
    );
  }

  Future<void> _saveAndDisplayVideo(
    Uint8List videoData,
    String senderIp,
  ) async {
    log('_listenForVideoStream _saveAndDisplayVideo $senderIp');

    try {
      String tempPath =
          '${Directory.systemTemp.path}/received_video_${DateTime.now().millisecondsSinceEpoch}.mp4';
      await File(tempPath).writeAsBytes(videoData);

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

      log('_listenForVideoStream Video saved to: $tempPath');
    } catch (e) {
      log('_listenForVideoStream Error saving video: $e');
    }
  }

  Future<void> _startPlayerForStream() async {
    if (!_isPlayerReady) {
      // if (_audioPlayer!.isStopped) {
      // await _audioPlayer!.startPlayerFromStream(
      //   codec: Codec.pcm16, //_codec,
      //   numChannels: cstCHANNELNB,
      //   sampleRate: cstSAMPLERATE, // tSTREAMSAMPLERATE, //tSAMPLERATE,
      //   interleaved: true,
      //   bufferSize: 1024,
      // );
      await _audioPlayer!.startPlayerFromStream(
        codec: Codec.pcm16,
        numChannels: 2,
        sampleRate: 48000,
        interleaved: true,
        bufferSize: 1024,
      );

      // await _audioPlayer!.startPlayerFromStream(
      //   codec: Codec.pcm16,
      //   numChannels: 2,
      //   sampleRate: 44100,
      //   // sampleRate: Platform.isIOS ? 44100 : 16000,
      //   interleaved: false,
      //   bufferSize: 2048,
      //   // bufferSize:
      //   //     // 8192,
      //   //     1024,
      // );
      _isPlayerReady = true;
      print("🎵 [CLIENT] Player initialized for streaming");
      // }
    }
  }

  Future<void> _stopPlayerForStream() async {
    if (_isPlayerReady) {
      await _audioPlayer!.stopPlayer();
      _isPlayerReady = false;
      print("🛑 [CLIENT] Player stopped");
    }
  }

  // Updated Real-Time Streaming Methods
  // Real-Time Streaming Methods
  void _startStreaming() async {
    if (_isStreaming || _isRecording) return;
    setState(() => _isStreaming = true);

    _audioStreamController = StreamController<Uint8List>();
    _audioStreamController!.stream.listen(_sendStreamedAudio);

    await _audioRecorder!.startRecorder(
      codec: Codec.pcm16,
      numChannels: 2,
      sampleRate: 48000,
      // sampleRate: Platform.isIOS ? 44100 : 16000,
      bitRate: 16000,
      // bufferSize: 1024, // 8192
      bufferSize: 1024,
      toStream: _audioStreamController!.sink,
    );
  }

  void _stopStreaming() async {
    if (!_isStreaming) return;
    setState(() => _isStreaming = false);
    await _audioRecorder!.stopRecorder();
    await _audioStreamController?.close();

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

    _audioStreamController = null;
    print("🛑 [CLIENT] Stopped streaming");
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

    // for (var audio in bufferUint8) {
    //   for (String ip in connectedUsers) {
    //     if (ip != _myIpAddress) {
    //       UDP sender = await UDP.bind(Endpoint.any());
    //       await sender.send(
    //         audio,
    //         Endpoint.unicast(InternetAddress(ip), port: Port(6006)),
    //       );
    //       sender.close();
    //     }
    //   }
    // }
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
    UDP receiver = await UDP.bind(Endpoint.any(port: Port(6006)));
    print("🔄 [CLIENT] Listening for streamed audio on port 6006...");

    receiver.asStream().listen((datagram) async {
      if (datagram != null && datagram.data.isNotEmpty) {
        Uint8List audioData = datagram.data;

        // // ✅ Stop signal
        // if (audioData.length == 4 && audioData.every((b) => b == 0xFF)) {
        //   await _stopPlayerForStream();
        //   _silenceTimer?.cancel();
        //   print("🛑 [CLIENT] Received stop signal");
        //   return;
        // }

        // Check for stop signal
        if (audioData.length == 4 &&
            audioData[0] == 0xFF &&
            audioData[1] == 0xFF &&
            audioData[2] == 0xFF &&
            audioData[3] == 0xFF) {
          await _stopPlayerForStream();
          _silenceTimer?.cancel();
          return;
        }

        // Ensure player is ready before feeding data
        await _startPlayerForStream();

        // Reset silence timer
        _silenceTimer?.cancel();
        _silenceTimer = Timer(Duration(milliseconds: 100), () async {
          await _stopPlayerForStream();
          print("🔇 [CLIENT] No audio for 500ms, stopping player...");
        });

        // Feed audio data
        try {
          print("📥 Received audio chunk size: ${audioData.length}");
          await _audioPlayer!.feedUint8FromStream(audioData);
        } catch (e) {
          print("⚠️ [CLIENT] Error feeding audio stream: $e");
        }
      }
    });
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
    await _audioPlayer!.startPlayer(fromURI: tempPath, codec: Codec.aacADTS);
  }

  void _startRecording() async {
    if (_isRecording) return;

    setState(() {
      _isRecording = true;
    });

    await _audioRecorder!.startRecorder(
      toFile: 'audio.aac',
      codec: Codec.aacADTS,
    );

    _audioRecorder!.onProgress!.listen((RecordingDisposition disposition) {
      // Handle recording progress if needed
    });
  }

  void _stopRecording() async {
    if (!_isRecording) return;

    setState(() {
      _isRecording = false;
    });

    String? path = await _audioRecorder!.stopRecorder();
    if (path != null) {
      Uint8List audioData = await File(path).readAsBytes();
      _sendAudioData(audioData);
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

  // void _listenForAudio() async {
  //   UDP receiver = await UDP.bind(Endpoint.any(port: Port(6005)));
  //   print("🔄 [CLIENT] Listening for audio on port 6005...");
  //
  //   receiver.asStream().listen((datagram) async {
  //     if (datagram != null && datagram.data.isNotEmpty) {
  //       Uint8List audioData = datagram.data;
  //       await _playAudio(audioData);
  //     }
  //   });
  // }
  //
  // Future<void> _playAudio(Uint8List audioData) async {
  //   String tempPath = '${Directory.systemTemp.path}/audio.aac';
  //   await File(tempPath).writeAsBytes(audioData);
  //   await _audioPlayer!.startPlayer(fromURI: tempPath, codec: Codec.aacADTS);
  // }

  // Future<void> _playAudio(Uint8List audioData) async {
  //   String tempPath = '${Directory.systemTemp.path}/audio.aac';
  //   await File(tempPath).writeAsBytes(audioData);
  //   await _audioPlayer!.startPlayer(fromURI: tempPath, codec: Codec.aacADTS);
  // }

  void _startReceivingRequests() async {
    udpSocket = await UDP.bind(
      Endpoint.any(port: Port(6002)),
    ); // Host listens on 6002
    print("🔵 [HOST] Listening for join requests on port 6002...");

    // Add the host itself to the list

    String hostIp = widget.hostIp;
    if (!connectedUsers.contains(hostIp)) {
      setState(() {
        connectedUsers.add(hostIp);
      });
    }

    udpSocket!.asStream().listen((datagram) async {
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

          if (!connectedUsers.contains(userIp)) {
            setState(() {
              connectedUsers.add(userIp);
            });
          }
          _broadcastUserList();

          // ✅ Send confirmation to new client
          UDP sender = await UDP.bind(Endpoint.any());
          await sender.send(
            "JOINED".codeUnits,
            Endpoint.unicast(InternetAddress(userIp), port: Port(6003)),
          );
          sender.close();
        }
      }
    });
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
    print("🔄 [CLIENT] Listening for user list updates on port 6003...");

    receiver.asStream().listen(
      (datagram) {
        if (datagram != null && datagram.data.isNotEmpty) {
          String receivedData = String.fromCharCodes(datagram.data);
          List<String> updatedUsers = receivedData.split(',');
          print("receivedData $receivedData");

          if (receivedData.contains(',') ||
              RegExp(r'^(\d{1,3}\.){3}\d{1,3}$').hasMatch(receivedData)) {
            List<String> updatedUsers = receivedData.split(',');
            print("🔄 [CLIENT] Received updated user list: $updatedUsers");

            setState(() {
              connectedUsers = updatedUsers;
            });
          }
          // print(
          //     "🔄 [CLIENT] Received updated user list: $updatedUsers"); // Debug log
          //
          // setState(() {
          //   print("connectedUsers IP ADDRESS$connectedUsers");
          //
          //   connectedUsers = updatedUsers;
          // });

          print("🔄 [CLIENT] State updated with: $connectedUsers");
        }
      },
      onError: (error) {
        print("❌ [CLIENT] Error receiving user list updates: $error");
      },
    );
  }

  TextEditingController messageController = TextEditingController();
  List<String> messages = []; // Stores received messages

  void _sendMessage(String message) async {
    if (message.trim().isEmpty) return;

    Uint8List data = Uint8List.fromList(message.codeUnits);
    print("📢 Sending message: $message");

    // Ensure message is sent to all users, including the host
    for (String ip in connectedUsers) {
      UDP sender = await UDP.bind(Endpoint.any());
      await sender.send(
        data,
        Endpoint.unicast(InternetAddress(ip), port: Port(6004)),
      );
      sender.close();
    }

    // setState(() {
    //   messages.add("You: $message"); // Show sent message in chat
    // });

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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      _cameraController?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      if (_cameraController != null) {
        _initCamera();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: true,
      top: true,
      right: true,
      left: true,
      child: Scaffold(
        // resizeToAvoidBottomInset :false,
        extendBodyBehindAppBar: true,
        // appBar: AppBar(title: Text(''), automaticallyImplyLeading: false),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFF6767), Color(0xFF11E0DC)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            children: [
              SizedBox(height: kToolbarHeight),

              // Camera Preview Section
              if (_isCameraInitialized)
                Container(
                  height: 200,
                  margin: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: CameraPreview(_cameraController!),
                  ),
                ),

              Text(
                "Connected Users",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              if (connectedUsers.isEmpty)
                Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text(
                    "No users connected yet",
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                )
              else
                Column(
                  children: connectedUsers.map((ip) {
                    bool isHost = ip == widget.hostIp;
                    bool isMe = ip == _myIpAddress;

                    String displayText;
                    if (isHost && isMe) {
                      displayText = "You";
                    } else if (isHost) {
                      displayText = "Host";
                    } else if (isMe) {
                      displayText = "You";
                    } else {
                      displayText = "User";
                    }

                    return Container(
                      margin: EdgeInsets.symmetric(vertical: 4, horizontal: 16),
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.grey.shade300,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isHost ? Icons.cell_tower : Icons.person,
                            color: isHost ? Colors.blueGrey : Colors.blueGrey,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            "$displayText: $ip",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),

              // SizedBox(height: 0),
              // Text("Chat Messages",
              //     style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Expanded(
                child: Container(
                  margin: EdgeInsets.all(10),
                  padding: EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: messages.isEmpty
                      ? Center(
                          child: Text(
                            "No messages yet",
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            return Container(
                              margin: EdgeInsets.symmetric(vertical: 5),
                              padding: EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: messages[index].startsWith("You:")
                                    ? Colors.green[100] // Sent message
                                    : Colors.white, // Received message
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                messages[index],
                                style: TextStyle(fontSize: 14),
                              ),
                            );
                          },
                        ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(30),
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
                        ),
                      ),
                      IconButton(
                        onPressed: () => _sendMessage(messageController.text),
                        icon: Icon(Icons.send, color: Colors.blueAccent),
                        splashRadius: 24,
                      ),
                    ],
                  ),
                ),
              ),

              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    "Video Recording",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),

                  Text(
                    "Voice Message",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Video Recording Button
                      IconButton(
                        onPressed: _isRecordingVideo
                            ? _stopVideoRecording
                            : _startVideoRecording,
                        icon: Icon(
                          _isRecordingVideo
                              ? Icons.videocam_off
                              : Icons.videocam,
                          size: 36,
                          color: _isRecordingVideo
                              ? Colors.redAccent
                              : Colors.blueAccent,
                        ),
                        tooltip: _isRecordingVideo
                            ? 'Stop Video Recording'
                            : 'Start Video Recording',
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.grey[200],
                          padding: EdgeInsets.all(12),
                          shape: CircleBorder(),
                          shadowColor: Colors.black.withOpacity(0.2),
                          elevation: 4,
                        ),
                      ),
                      SizedBox(width: 16),

                      // Recording Button
                      IconButton(
                        onPressed: _isRecording
                            ? _stopRecording
                            : _startRecording,
                        icon: Icon(
                          _isRecording ? Icons.stop_circle : Icons.mic,
                          size: 36,
                          color: _isRecording
                              ? Colors.redAccent
                              : Colors.blueAccent,
                        ),
                        tooltip: _isRecording
                            ? 'Stop Recording'
                            : 'Start Recording',
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.grey[200],
                          padding: EdgeInsets.all(12),
                          shape: CircleBorder(),
                          shadowColor: Colors.black.withOpacity(0.2),
                          elevation: 4,
                        ),
                      ),
                      SizedBox(width: 16),

                      // Push-to-Talk Button
                      IconButton(
                        onPressed: _isStreaming
                            ? _stopStreaming
                            : _startStreaming,
                        icon: Icon(
                          _isStreaming ? Icons.cancel : Icons.record_voice_over,
                          size: 36,
                          color: _isStreaming
                              ? Colors.orangeAccent
                              : Colors.greenAccent,
                        ),
                        tooltip: _isStreaming ? 'Stop Talking' : 'Push to Talk',
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.grey[200],
                          padding: EdgeInsets.all(12),
                          shape: CircleBorder(),
                          shadowColor: Colors.black.withOpacity(0.2),
                          elevation: 4,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              SizedBox(height: kToolbarHeight),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    _videoChunkTimer?.cancel();
    udpSocket?.close();
    _audioRecorder?.closeRecorder();
    _audioPlayer?.closePlayer();
    _audioStreamController?.close();
    super.dispose();
  }
}
