import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:push_to_talk_app/presentation/bloc/camera_bloc.dart';
import 'package:push_to_talk_app/core/services/network_service.dart';
import 'package:push_to_talk_app/core/utils/camera_utils.dart';
import 'package:push_to_talk_app/core/utils/permission_utils.dart';
import 'package:push_to_talk_app/presentation/pages/udp/components/history_voice_recording_component.dart';
import 'package:push_to_talk_app/core/helpers/file_transfer.dart';
import 'package:push_to_talk_app/data/model/video_recording_model.dart';
import 'package:push_to_talk_app/data/model/voice_recording_model.dart';
import 'package:push_to_talk_app/presentation/pages/video_call/walkie_talkie_video_call.dart';
import 'package:push_to_talk_app/presentation/pages/video_recorder/pages/record_video_page.dart';
import 'package:push_to_talk_app/presentation/pages/video_recorder/widgets/video_path_dialog.dart';
import 'package:udp/udp.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:uuid/uuid.dart';

class LobbyScreen extends StatefulWidget with WidgetsBindingObserver {
  static const String id = 'lobby_screen';
  final bool isHost;
  final String hostIp; // Host's IP
  final String lobbyId; // Pass the lobby ID

  const LobbyScreen({
    super.key,
    required this.isHost,
    required this.hostIp,
    required this.lobbyId,
  });

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> with WidgetsBindingObserver {
  // List<String> connectedUsers = []; // Stores connected IPs
  final ValueNotifier<List<String>> _connectedUsersNotifier =
      ValueNotifier<List<String>>([]); // Real-time connected users
  final NetworkService networkService = NetworkService();

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

  final Map<String, Socket> _tcpConnections = {};
  bool _isTcpInitialized = false;
  Completer<void>? _tcpInitializationCompleter;
  // TCP connection management
  final Map<String, Socket> _activeTcpConnections = {};
  bool _isTcpHealthy = false;
  Timer? _tcpHealthCheckTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _audioRecorder = FlutterSoundRecorder();
    _audioPlayer = FlutterSoundPlayer();
    _progressController = StreamController<double>.broadcast();

    _initAudio();
    _loadVoiceRecordings();

    // Inisialisasi koneksi secara sequential
    _initializeTcpConnections().then((_) {
      _initializeConnections();
    });
  }

  Future<void> _initializeTcpConnections() async {
    await getLocalIp();

    if (widget.isHost) {
      await _startRobustTcpServer();
    } else {
      await _connectToTcpServer();
    }

    _startTcpHealthCheck();
  }

  Future<void> _initializeConnections() async {
    // Tunggu IP address tersedia
    await getLocalIp();

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
    _listenForVideoCall();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    print("🔄 App Lifecycle State: $state");

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        // App masuk background
        log("📱 App masuk background at ${DateTime.now()}");

        break;

      case AppLifecycleState.resumed:
        // App kembali ke foreground
        log("📱 App kembali ke foreground");

        break;

      case AppLifecycleState.detached:
        // App benar-benar di-close
        log("❌ App di-DETACHED - cleaning up");

        break;

      case AppLifecycleState.hidden:
        log("📱 App HIDDEN");
        break;
    }
  }

  Future<void> _notifyUserLeft() async {
    // Kirim notifikasi LEAVE hanya ketika app benar-benar di-close
    if (!widget.isHost && widget.hostIp.isNotEmpty) {
      try {
        UDP sender = await UDP.bind(Endpoint.any());
        await sender.send(
          Uint8List.fromList("LEAVE".codeUnits),
          Endpoint.unicast(InternetAddress(widget.hostIp), port: Port(6002)),
        );
        sender.close();
        print("📤 [CLIENT] Sent leave notification to host");
      } catch (e) {
        print("❌ Error sending leave message: $e");
      }
    } else if (widget.isHost) {
      // Host notify semua client
      try {
        for (String ip in connectedUsers) {
          if (ip != _myIpAddress) {
            UDP sender = await UDP.bind(Endpoint.any());
            await sender.send(
              Uint8List.fromList("HOST_LEAVING".codeUnits),
              Endpoint.unicast(InternetAddress(ip), port: Port(6003)),
            );
            sender.close();
          }
        }
        print("📤 [HOST] Notified all clients about host leaving");
      } catch (e) {
        print("❌ Error notifying clients: $e");
      }
    }
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

  void _startReceivingRequests() async {
    udpSocket = await UDP.bind(
      Endpoint.any(port: Port(6002)),
    ); // Host listens on 6002
    log("🔵 [HOST] Listening for join requests on port 6002...");

    // Add the host itself to the list
    String hostIp = widget.hostIp;
    _addUser(hostIp);

    udpSocket?.asStream().listen((datagram) async {
      if (datagram != null) {
        String message = String.fromCharCodes(datagram.data);
        String userIp = datagram.address.address;

        if (message == "MotoVox_DISCOVER") {
          log(
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
          log("✅ [HOST] Join request received from: $userIp");

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
          log("🚪 [HOST] Leave request received from: $userIp");
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
      log("➕ [USERS] User added: $userIp, Total: ${connectedUsers.length}");
    }
  }

  void _removeUser(String userIp) {
    if (connectedUsers.contains(userIp)) {
      _connectedUsersNotifier.value = connectedUsers
          .where((ip) => ip != userIp)
          .toList();
      log("➖ [USERS] User removed: $userIp, Total: ${connectedUsers.length}");
    }
  }

  void _sendJoinRequest() async {
    log(
      "📩 [CLIENT] Sending join request to: ${widget.hostIp}:6002",
    ); // Debug log

    if (widget.hostIp.isEmpty) {
      log("❌ Invalid Host IP");
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
    log("📩 [CLIENT] Join request sent to ${widget.hostIp}");
  }

  void _broadcastUserList() async {
    if (connectedUsers.isEmpty) return;

    String userList = connectedUsers.join(',');
    Uint8List data = Uint8List.fromList(userList.codeUnits);

    log("📢 [HOST] Sending updated user list: $userList");

    for (String ip in connectedUsers) {
      UDP sender = await UDP.bind(Endpoint.any());
      await sender.send(
        data,
        Endpoint.unicast(InternetAddress(ip), port: Port(6003)),
      );
      sender.close();
    }
  }

  // keep-alive mechanism
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

  Future<void> _initAudio() async {
    await _audioPlayer?.openPlayer().then((value) async {
      await _openRecorder();
    });
    await _startPlayerForStream(); // Initial setup
  }

  Future<void> _openRecorder() async {
    var status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      throw RecordingPermissionException('Microphone permission not granted');
    }
    await _audioRecorder!.openRecorder();

    await _audioRecorder!.setSubscriptionDuration(
      const Duration(milliseconds: 100),
    ); // DO NOT FORGET THIS CALL !!!
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
          _showInfoSnackbar('No videos found');
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
            _showInfoSnackbar('No videos found');
          }
          return;
        }

        log("sendvideo 📁 Videos in directory: ${videoFiles.length}");
        List<VideoRecording> videoRecordings = [];
        for (var file in videoFiles) {
          log("sendvideo   - ${file.path.split('/').last}");
          if (file.path.toLowerCase().endsWith('.mp4') ||
              file.path.toLowerCase().endsWith('.mov')) {
            String fileName = file.path.split('/').last;
            DateTime timestamp = (await file.stat()).modified;
            setState(() {
              videoRecordings.add(
                VideoRecording(
                  filePath: file.path,
                  fileName: fileName,
                  timestamp: timestamp,
                  duration: 0, // You might want to calculate this
                  senderIp: _myIpAddress,
                ),
              );
            });
          }
        }

        // Show dialog with video list
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Received Videos (${videoRecordings.length})'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: videoRecordings.length,
                itemBuilder: (context, index) {
                  String fileName = videoRecordings[index].fileName;
                  String videoSender = "You";

                  if (videoRecordings[index].fileName.contains('_from_')) {
                    final parts = videoRecordings[index].fileName.split(
                      '_from_',
                    );
                    if (parts.length > 1) {
                      videoSender = parts[1].replaceAll('.mp4', '');
                    }
                  }

                  return ListTile(
                    leading: Icon(Icons.video_library, color: Colors.blue),
                    title: Text(
                      '${fileName}',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "From: $videoSender",
                          style: TextStyle(fontSize: 12),
                        ),
                        Text(
                          _formatDateTime(videoRecordings[index].timestamp),
                          style: TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                      ],
                    ),
                    onTap: () {
                      // Play the video
                      Navigator.pop(context);
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (context) =>
                            VideoPathDialog(videoPath: videoFiles[index].path),
                      );
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
        _showSuccessSnackbar('Video deleted');
      }
    } catch (e) {
      log("❌ Error deleting video: $e");
      if (mounted) {
        _showErrorSnackbar('Failed to delete video');
      }
    }
  }

  Future<void> _startPlayerForStream() async {
    if (!_isPlayerReady) {
      await _audioPlayer?.startPlayerFromStream(
        codec: Codec.pcm16,
        numChannels: 2,
        sampleRate: Platform.isIOS ? 44100 : 16000,
        // sampleRate: 48000,
        interleaved: true,
        bufferSize: 1024,
      );

      _isPlayerReady = true;
      log("🎵 [CLIENT] Player initialized for streaming");
      // }
    }
  }

  Future<void> _stopPlayerForStream() async {
    if (_isPlayerReady) {
      await _audioPlayer?.stopPlayer();
      _isPlayerReady = false;
      log("🛑 [CLIENT] Player stopped");
    }
  }

  // Updated Real-Time Streaming Methods
  // Real-Time Streaming Methods
  void _startVoiceStreaming() async {
    if (_isStreaming || _isRecording) return;
    setState(() => _isStreaming = true);

    _audioStreamController = StreamController<Uint8List>();
    _audioStreamController!.stream.listen(_sendStreamedAudio);

    await _audioRecorder!.startRecorder(
      codec: Codec.pcm16,
      numChannels: 2,
      // sampleRate: 48000,
      sampleRate: Platform.isIOS ? 44100 : 16000,
      bitRate: 16000,
      // bufferSize: 1024, // 8192
      bufferSize: 1024,
      toStream: _audioStreamController!.sink,
    );
  }

  void _stopVoiceStreaming() async {
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
    log("🛑 [AUDIO] Stopped streaming successfully");
    log("🛑 [CLIENT] Stopped streaming");
  }

  void _sendStreamedAudio(Uint8List audioChunk) async {
    if (audioChunk.isEmpty || audioChunk.length % 2 != 0) return;

    // Gunakan connection map yang sama untuk konsistensi
    final usersToSend = List.from(connectedUsers)..remove(_myIpAddress);

    if (usersToSend.isEmpty) return;

    List<Future> sendFutures = [];

    for (String ip in usersToSend) {
      sendFutures.add(_sendAudioToUser(ip, audioChunk));
    }

    // Jalankan semua secara parallel, ignore errors
    await Future.wait(sendFutures, eagerError: false);
  }

  Future<void> _sendAudioToUser(String ip, Uint8List audioChunk) async {
    try {
      UDP sender = await UDP.bind(Endpoint.any());
      await sender.send(
        audioChunk,
        Endpoint.unicast(InternetAddress(ip), port: Port(6006)),
      );
      sender.close();
    } catch (e) {
      log("❌ Failed to send audio to $ip: $e");
      // Tidak perlu rethrow, biarkan user lain tetap menerima
    }
  }

  void _listenForStreamedAudio() async {
    try {
      UDP receiver = await UDP.bind(Endpoint.any(port: Port(6006)));
      log("🔄 [CLIENT] Listening for streamed audio on port 6006...");

      receiver.asStream().listen(
        (datagram) async {
          if (datagram != null && datagram.data.isNotEmpty) {
            Uint8List audioData = datagram.data;

            // Validate data before processing
            if (audioData.length % 2 != 0) {
              log(
                "⚠️ Skipping misaligned audio chunk: ${audioData.length} bytes",
              );
              return;
            }

            // Check for stop signal
            if (audioData.length == 4 &&
                audioData[0] == 0xFF &&
                audioData[1] == 0xFF &&
                audioData[2] == 0xFF &&
                audioData[3] == 0xFF) {
              log("🛑 [AUDIO] Received stop signal");
              await _stopPlayerForStream();
              _silenceTimer?.cancel();
              return;
            }

            // Process valid audio data
            await _processAudioData(audioData);
          }
        },
        onError: (error) {
          log("❌ [AUDIO] UDP reception error: $error");
        },
      );
    } catch (e) {
      log("❌ [AUDIO] Error binding UDP socket: $e");
    }
  }

  Future<void> _processAudioData(Uint8List audioData) async {
    try {
      await _startPlayerForStream();

      _silenceTimer?.cancel();
      _silenceTimer = Timer(Duration(milliseconds: 500), () async {
        await _stopPlayerForStream();
        log("🔇 [CLIENT] No audio for 500ms, stopping player...");
      });

      log("📥 Received audio chunk size: ${audioData.length}");

      _audioPlayer?.uint8ListSink!.add(audioData);
    } catch (e) {
      log("❌ [AUDIO] Error processing audio: $e");
    }
  }

  void _listenForAudio() async {
    UDP receiver = await UDP.bind(Endpoint.any(port: Port(6005)));
    log("🔄 [CLIENT] Listening for audio on port 6005...");

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

  void _startVoiceRecording() async {
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

  void _stopVoiceRecording() async {
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
      _sendVoiceRecordData(audioData);

      // Also send as voice recording file for history
      await _sendVoiceRecording(path);
    }
  }

  void _sendVoiceRecordData(Uint8List audioData) async {
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
    log("🔄 [CLIENT] Listening for messages on port 6004...");

    receiver.asStream().listen((datagram) {
      if (datagram != null && datagram.data.isNotEmpty) {
        String receivedMessage = String.fromCharCodes(datagram.data);
        log("💬 New message received: $receivedMessage");

        setState(() {
          messages.add(receivedMessage);
        });
      }
    });
  }

  //video call
  //
  void _sendVideoCallMessage(String message, String clientIPAdress) async {
    if (message.trim().isEmpty) return;

    Uint8List data = Uint8List.fromList(message.codeUnits);
    log("📢 Sending message: $message");

    // Ensure message is sent to all users, including the host
    // for (String ip in connectedUsers) {
    UDP sender = await UDP.bind(Endpoint.any());
    await sender.send(
      data,
      Endpoint.unicast(InternetAddress(clientIPAdress), port: Port(6020)),
    );
    sender.close();
    // }

    // messageController.clear();
  }

  void _listenForVideoCall() async {
    UDP receiver = await UDP.bind(Endpoint.any(port: Port(6020)));
    log("🔄 [CLIENT] Listening for video call messages on port 6020...");

    receiver.asStream().listen((datagram) {
      if (datagram != null && datagram.data.isNotEmpty) {
        String receivedVideoCallId = String.fromCharCodes(datagram.data);
        log("💬 New video call message received: $receivedVideoCallId");

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) {
              return WalkieTalkieVideoCall(
                controllerIdCall: receivedVideoCallId, // ID dari caller
                clientIPAdress: _myIpAddress,
                isInitiator: false, // Ini adalah callee
              );
            },
          ),
        );
      }
    });
  }

  // Check and maintain TCP connections
  Future<void> _ensureTcpConnections() async {
    log("🔧 Ensuring TCP connections...");

    if (widget.isHost) {
      await _ensureTcpServerRunning();
    } else {
      await _ensureTcpClientConnected();
    }

    _startTcpHealthCheck();
  }

  Future<void> _ensureTcpServerRunning() async {
    if (_tcpServer == null || _tcpServer!.isBroadcast) {
      log("🔄 Restarting TCP server...");
      await _startTcpServer();
    }
  }

  Future<void> _ensureTcpClientConnected() async {
    if (_tcpClients.isEmpty || !_isTcpConnectionHealthy()) {
      log("🔄 Reconnecting TCP client...");
      await _connectToTcpServer();
    }
  }

  bool _isTcpConnectionHealthy() {
    for (Socket client in _tcpClients) {
      try {
        // Try to get remote address - if it throws, connection is dead
        client.remoteAddress;
        return true;
      } catch (e) {
        return false;
      }
    }
    return false;
  }

  void _startTcpHealthCheck() {
    _tcpHealthCheckTimer?.cancel();
    _tcpHealthCheckTimer = Timer.periodic(Duration(seconds: 10), (timer) async {
      if (_isDisposed) {
        timer.cancel();
        return;
      }

      if (!_isTcpConnectionHealthy()) {
        log("⚠️ TCP connection unhealthy, attempting repair...");
        await _ensureTcpConnections();
      }
    });
  }

  // TCP Server for reliable file transfer
  Future<void> _startTcpServer() async {
    try {
      // Close existing server jika ada
      await _tcpServer?.close();
      await Future.delayed(Duration(milliseconds: 100));

      _tcpServer = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        TCP_FILE_PORT,
        shared: true, // ✅ ADD THIS LINE
      );

      log("🚀 [HOST] TCP File Server started on port $TCP_FILE_PORT");

      _tcpServer?.listen(
        (Socket client) {
          String clientIp = client.remoteAddress.address;
          log("📁 [HOST] New TCP client connected: $clientIp");

          // Simpan koneksi ke Map
          _tcpClients.add(client);
          _handleIncomingFiles(client, clientIp);

          client.done.then((_) {
            log("📁 [HOST] TCP client disconnected: $clientIp");
            _tcpClients.remove(client);
            log("sendvideo _startTcpServer 📁 [HOST] TCP client disconnected");
          });
        },
        onError: (error) {
          log("❌ [HOST] TCP Server error: $error");
        },
      );
    } catch (e) {
      log("❌ [HOST] Error starting TCP server: $e");

      // Coba bind ke port yang berbeda sebagai fallback
      await _startTcpServerWithFallback();
    }
  }

  Future<void> _startTcpServerWithFallback() async {
    const List<int> fallbackPorts = [6012, 6013, 6014, 6015];

    for (int port in fallbackPorts) {
      try {
        log("🔄 Trying fallback port: $port");

        _tcpServer = await ServerSocket.bind(
          InternetAddress.anyIPv4,
          port,
          shared: true,
        );

        log("✅ [HOST] TCP Server started on fallback port: $port");
        break;
      } catch (e) {
        log("❌ Failed to bind to port $port: $e");
        if (port == fallbackPorts.last) {
          rethrow; // Jika semua port gagal
        }
      }
    }
  }

  void _handleIncomingFiles(Socket client, String clientIp) {
    ByteData? headerData;
    int expectedFileSize = 0;
    int expectedNameSize = 0;
    Uint8List? fileNameBytes;
    Uint8List? fileBuffer;
    int bytesReceived = 0;

    log("📥 Incoming TCP data handler started for: $clientIp");

    client.listen(
      (data) async {
        int offset = 0;

        while (offset < data.length) {
          // Header belum terbaca → baca header dulu
          if (headerData == null) {
            if (data.length - offset >= 8) {
              headerData = ByteData.sublistView(data, offset, offset + 8);
              expectedFileSize = headerData!.getUint32(0, Endian.big);
              expectedNameSize = headerData!.getUint32(4, Endian.big);

              offset += 8;
            } else {
              return;
            }
          }

          // Nama file belum dibaca
          if (fileNameBytes == null) {
            if (data.length - offset >= expectedNameSize) {
              fileNameBytes = Uint8List.sublistView(
                data,
                offset,
                offset + expectedNameSize,
              );
              offset += expectedNameSize;

              fileBuffer = Uint8List(expectedFileSize);
              bytesReceived = 0;
            } else {
              return;
            }
          }

          // Baca isi file
          int remaining = expectedFileSize - bytesReceived;
          int toCopy = (data.length - offset).clamp(0, remaining);

          if (toCopy > 0) {
            fileBuffer!.setRange(
              bytesReceived,
              bytesReceived + toCopy,
              data.sublist(offset, offset + toCopy),
            );
          }

          offset += toCopy;
          bytesReceived += toCopy;

          // Jika selesai menerima file
          if (bytesReceived >= expectedFileSize) {
            String fileName = String.fromCharCodes(fileNameBytes!);

            log(
              "📥 File received from $clientIp: $fileName ($expectedFileSize bytes)",
            );

            // Save file locally
            await _saveReceivedFile(fileBuffer!, fileName);

            // Host RELAY ke semua client lain
            if (widget.isHost) {
              await _relayFileToOtherClients(fileBuffer!, fileName, clientIp);
            }

            // Reset state for next file
            headerData = null;
            expectedFileSize = 0;
            expectedNameSize = 0;
            fileNameBytes = null;
            fileBuffer = null;
            bytesReceived = 0;
          }
        }
      },
      onError: (e) {
        log("❌ TCP Client error: $e");
      },
      onDone: () {
        log("📁 TCP connection closed: $clientIp");
        _tcpClients.remove(client);
      },
    );
  }

  // TCP Client connection for non-host clients
  Future<void> _connectToTcpServer() async {
    if (widget.isHost) return; // Host doesn't need to connect to itself

    try {
      Socket client = await Socket.connect(widget.hostIp, TCP_FILE_PORT);
      _tcpClients.add(client);
      log(
        "sendvideo _connectToTcpServer 🔗 [CLIENT] Connected to TCP server at ${widget.hostIp}:$TCP_FILE_PORT",
      );

      // Listen for incoming files from host
      _handleIncomingFiles(client, client.address.address);
    } catch (e) {
      log(
        "sendvideo _connectToTcpServer ❌ [CLIENT] Error connecting to TCP server: $e",
      );
    }
  }

  // Enhanced video file sending with better error handling and local saving
  Future<void> _sendVideoFileOverTCP(XFile videoFile) async {
    log("📤 Starting enhanced video file transfer...");

    // Ensure TCP connections are healthy
    await _ensureTcpConnections();

    // Check if we have any active connections
    if (_tcpClients.isEmpty && !widget.isHost) {
      final errorMsg =
          "❌ No TCP connections available. Please check network connection.";
      log(errorMsg);
      _showErrorSnackbar("Failed to send video: No network connection");
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
    int successfulSends = 0;
    List<String> failedIps = [];

    try {
      // Read video data
      Uint8List videoData = await videoFile.readAsBytes();
      totalBytes = videoData.length;

      // Save file locally on sender device first
      final String localFilePath = await _saveVideoLocally(
        videoData,
        _myIpAddress,
      );
      log("💾 Video saved locally at: $localFilePath");

      // Prepare file metadata
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String originalFileName = 'video_${timestamp}.mp4';
      final String senderFileName = 'sent_video_${timestamp}.mp4'; // For sender
      final String receiverFileName =
          'video_${timestamp}_from_${_myIpAddress.replaceAll('.', '_')}.mp4'; // For receivers

      // Start progress updates
      progressTimer = Timer.periodic(Duration(milliseconds: 100), (timer) {
        if (bytesSent >= totalBytes) {
          timer.cancel();
          _progressController?.add(1.0);
        } else {
          double progress = bytesSent / totalBytes;
          _progressController?.add(progress);
        }
      });

      // Create file header with receiver-specific filename
      Uint8List fileNameBytes = Uint8List.fromList(receiverFileName.codeUnits);
      Uint8List header = Uint8List(8 + fileNameBytes.length);
      ByteData headerData = ByteData.view(header.buffer);
      headerData.setUint32(0, videoData.length, Endian.big);
      headerData.setUint32(4, fileNameBytes.length, Endian.big);
      header.setRange(8, 8 + fileNameBytes.length, fileNameBytes);

      // Send to all connected clients
      final List<Socket> clientsToSend = _getValidTcpClients();

      if (clientsToSend.isEmpty) {
        throw Exception("No valid TCP connections available");
      }

      log("📤 Sending video to ${clientsToSend.length} client(s)");

      // Send to each client with individual error handling
      for (Socket client in clientsToSend) {
        final clientIp = client.remoteAddress.address;

        try {
          // Verify connection is still alive
          client.remoteAddress;

          // Send header and file data
          client.add(header);
          client.add(videoData);
          await client.flush();

          bytesSent = totalBytes; // Mark as complete for progress
          successfulSends++;

          log("✅ Video successfully sent to $clientIp");
        } catch (e) {
          log("❌ Failed to send to $clientIp: $e");
          failedIps.add(clientIp);

          // Remove broken connection
          _tcpClients.remove(client);
          try {
            client.destroy();
          } catch (destroyError) {
            log("⚠️ Error destroying broken connection: $destroyError");
          }
        }
      }

      //  Handle results
      await Future.delayed(Duration(milliseconds: 500)); // Show completion

      final String resultMessage = _buildTransferResultMessage(
        successfulSends,
        failedIps,
        clientsToSend.length,
      );

      log("📊 Transfer completed: $resultMessage");

      if (mounted) {
        successfulSends > 0
            ? _showSuccessSnackbar(resultMessage)
            : _showErrorSnackbar(resultMessage);
      }

      // If all failed and we're not host, try to reconnect
      if (successfulSends == 0 && !widget.isHost) {
        log("🔄 All sends failed, attempting TCP reconnection...");
        await _reconnectTcpWithRetry();
      }
    } catch (e) {
      log("❌ Critical error in video transfer: $e");

      if (mounted) {
        _showErrorSnackbar('Failed to send video: ${e.toString()}');
      }
    } finally {
      progressTimer?.cancel();
      setState(() {
        _isSendingFile = false;
      });
      _hideFileTransferProgressDialog();
    }
  }

  // Get valid TCP clients excluding self
  List<Socket> _getValidTcpClients() {
    return _tcpClients.where((client) {
      try {
        return client.remoteAddress.address != _myIpAddress;
      } catch (e) {
        return false; // Remove invalid clients
      }
    }).toList();
  }

  // Build transfer result message
  String _buildTransferResultMessage(
    int successful,
    List<String> failed,
    int total,
  ) {
    if (successful == total) {
      return 'Video sent successfully to $successful client(s)';
    } else if (successful > 0) {
      return 'Video sent to $successful client(s), failed: ${failed.length}';
    } else {
      return 'Failed to send video to any client. Please check connections.';
    }
  }

  // Enhanced TCP reconnection with retry
  Future<void> _reconnectTcpWithRetry() async {
    const int maxRetries = 3;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      log("🔄 TCP reconnection attempt $attempt/$maxRetries...");

      try {
        await _cleanupTcpResources();
        await Future.delayed(Duration(seconds: 1));

        if (widget.isHost) {
          await _startTcpServer();
        } else {
          await _connectToTcpServer();
        }

        // Verify connection is working
        if (_isTcpConnectionHealthy()) {
          log("✅ TCP reconnection successful on attempt $attempt");
          _showInfoSnackbar("Network connection restored");
          return;
        }
      } catch (e) {
        log("❌ TCP reconnection attempt $attempt failed: $e");
      }

      if (attempt < maxRetries) {
        await Future.delayed(Duration(seconds: 2));
      }
    }

    log("❌ All TCP reconnection attempts failed");
    _showErrorSnackbar(
      "Cannot establish network connection after $maxRetries attempts",
    );
  }

  // Save video locally on sender device
  Future<String> _saveVideoLocally(Uint8List videoData, String senderIp) async {
    try {
      final directory = await _getAppDirectory();
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();

      // Different naming for sender vs receiver
      final String fileName = senderIp == _myIpAddress
          ? 'sent_video_$timestamp.mp4' // Sender's copy
          : 'video_${timestamp}_from_${senderIp.replaceAll('.', '_')}.mp4'; // Receiver's copy

      final String filePath = '$directory/$fileName';

      await File(filePath).writeAsBytes(videoData);
      log("💾 Video saved locally: $filePath");

      return filePath;
    } catch (e) {
      log("❌ Error saving video locally: $e");
      rethrow;
    }
  }

  Future<void> _relayFileToOtherClients(
    Uint8List fileData,
    String fileName,
    String senderIp,
  ) async {
    log("📤 Relay: Host forwarding file from $senderIp to other clients...");

    Uint8List fileNameBytes = Uint8List.fromList(fileName.codeUnits);

    Uint8List header = Uint8List(8 + fileNameBytes.length);
    ByteData headerData = ByteData.view(header.buffer);

    headerData.setUint32(0, fileData.length, Endian.big);
    headerData.setUint32(4, fileNameBytes.length, Endian.big);
    header.setRange(8, 8 + fileNameBytes.length, fileNameBytes);

    int relayCount = 0;

    for (Socket client in List.from(_tcpClients)) {
      if (client.remoteAddress.address == senderIp) continue;

      try {
        client.add(header);
        client.add(fileData);
        await client.flush();
        relayCount++;

        log("📤 Relay success → ${client.remoteAddress.address}");
      } catch (e) {
        log("❌ Relay error to ${client.remoteAddress.address}: $e");
      }
    }

    log("📤 Relay done: forwarded to $relayCount client(s)");
  }

  // file saving for received files
  Future<void> _saveReceivedFile(Uint8List fileData, String fileName) async {
    try {
      // Save the received file with original name (includes sender IP)
      final String directory = await _getAppDirectory();
      final String filePath = '$directory/$fileName';

      await File(filePath).writeAsBytes(fileData);

      log("💾 Received file saved: $filePath");

      // Show success notification
      if (mounted) {
        _showSuccessSnackbar(
          'Video received: ${fileName.split('_from_').first}',
        );
      }

      log("sendvideo _saveReceivedFile 💾 File saved: $filePath");
      // Show video dialog
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Video Received'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Video saved successfully'),
                SizedBox(height: 8),
                Text(
                  'From: ${_extractSenderIpFromFileName(fileName)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (context) => VideoPathDialog(videoPath: filePath),
                  );
                },
                child: Text('Play Video'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Close'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      log("❌ Error saving received file: $e");
      if (mounted) {
        _showErrorSnackbar('Error saving received video');
      }
    }
  }

  // Extract sender IP from filename for display
  String _extractSenderIpFromFileName(String fileName) {
    try {
      final match = RegExp(r'from_([\d_]+)\.mp4').firstMatch(fileName);
      if (match != null) {
        return match.group(1)!.replaceAll('_', '.');
      }
      return 'Unknown';
    } catch (e) {
      return 'Unknown';
    }
  }

  Future<String> _getAppDirectory() async {
    final directory = Directory.systemTemp;
    return directory.path;
  }

  Future<void> _cleanupTcpResources() async {
    log("🧹 Cleaning up TCP resources...");

    // Close all TCP connections
    for (var connection in _tcpConnections.values) {
      try {
        await connection.flush();
        connection.destroy();
      } catch (e) {
        log("⚠️ Error closing TCP connection: $e");
      }
    }
    _tcpConnections.clear();

    // Close TCP server dengan proper handling
    if (_tcpServer != null) {
      try {
        await _tcpServer!.close();
        await Future.delayed(
          Duration(milliseconds: 200),
        ); // Tunggu socket benar-benar closed
        _tcpServer = null;
      } catch (e) {
        log("⚠️ Error closing TCP server: $e");
      }
    }

    // Cleanup legacy clients
    for (Socket client in _tcpClients) {
      try {
        client.destroy();
      } catch (e) {
        log("⚠️ Error destroying legacy TCP client: $e");
      }
    }
    _tcpClients.clear();

    _isTcpInitialized = false;
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
                        // Kirim notifikasi dan cleanup
                        await _notifyUserLeft();
                        await _cleanupAndLeave();
                        if (context.mounted) Navigator.of(context).pop(true);
                      },
                      child: const Text("Exit"),
                    ),
                  ],
                ),
              ) ??
              false;

          if (shouldExit && context.mounted) {
            Navigator.of(context).pop(result);
          }
        } else {
          // Untuk client, cukup cleanup dan pop
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
                            Align(
                              alignment: Alignment.center,
                              child: Text(
                                "Lobby : ${widget.lobbyId}",
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.right,
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

                                      return Container(
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
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (!isMe)
                                              Padding(
                                                padding: EdgeInsets.only(
                                                  left: 8,
                                                ),
                                                child: InkWell(
                                                  splashColor: Colors.red,
                                                  child: Icon(
                                                    Icons.video_call,
                                                    color: Colors.green,
                                                  ),
                                                  onTap: () {
                                                    final controllerIdCall =
                                                        Uuid().v4();
                                                    log(
                                                      "Tapped on $ip ($displayText) generate : ${Uuid().v4()}",
                                                    );
                                                    if (!isMe) {
                                                      Navigator.push(
                                                        context,
                                                        MaterialPageRoute(
                                                          builder: (context) {
                                                            return WalkieTalkieVideoCall(
                                                              controllerIdCall:
                                                                  controllerIdCall,
                                                              clientIPAdress:
                                                                  _myIpAddress,
                                                              isInitiator:
                                                                  true, // Ini adalah caller
                                                            );
                                                          },
                                                        ),
                                                      );
                                                      _sendVideoCallMessage(
                                                        controllerIdCall,
                                                        ip,
                                                      );
                                                      print(
                                                        "Tapped on $ip ($displayText)",
                                                      );
                                                    }
                                                  },
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
                                        child: SingleChildScrollView(
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
                                              child: RecordVideoPage(
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
                                          _stopVoiceRecording();
                                        } else {
                                          if (await PermissionUtils()
                                              .getCameraAndMicrophonePermissionStatus()) {
                                            _startVoiceRecording();
                                          } else {
                                            if (await PermissionUtils()
                                                .askForPermission()) {
                                              _startVoiceRecording();
                                            } else {
                                              log("Permission is denied");
                                              _showErrorSnackbar(
                                                'Microphone permission required',
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
                                          _stopVoiceStreaming();
                                        } else {
                                          if (await PermissionUtils()
                                              .getCameraAndMicrophonePermissionStatus()) {
                                            _startVoiceStreaming();
                                          } else {
                                            if (await PermissionUtils()
                                                .askForPermission()) {
                                              _startVoiceStreaming();
                                            } else {
                                              log("Permission is denied");
                                              _showErrorSnackbar(
                                                'Microphone permission required',
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
  Future<void> dispose() async {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);

    // Cleanup TCP connections
    log("🧹 Starting disposal process...");

    try {
      // 1. Cleanup TCP resources terlebih dahulu
      await _cleanupTcpResources();

      // 2. Tunggu untuk memastikan semua socket closed
      await Future.delayed(Duration(milliseconds: 500));

      await _cleanupAndLeave();
    } catch (e) {
      log("❌ Error during disposal: $e");
    } finally {
      if (widget.isHost) {
        networkService.removeLobby(widget.lobbyId);
      }
      super.dispose();
      log("✅ Disposal completed");
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
        print("📤 [CLIENT] Sent leave notification to host");
      } catch (e) {
        print("❌ Error sending leave message: $e");
      }
    } else if (widget.isHost) {
      // Host should notify all clients that they're leaving
      try {
        for (String ip in connectedUsers) {
          if (ip != _myIpAddress) {
            UDP sender = await UDP.bind(Endpoint.any());
            await sender.send(
              Uint8List.fromList("HOST_LEAVING".codeUnits),
              Endpoint.unicast(InternetAddress(ip), port: Port(6003)),
            );
            sender.close();
          }
        }
        print("📤 [HOST] Notified all clients about host leaving");
      } catch (e) {
        print("❌ Error notifying clients: $e");
      }
    }

    // Cleanup audio resources first
    try {
      _silenceTimer?.cancel();
      await _audioRecorder?.stopRecorder();
      await _audioPlayer?.stopPlayer();
      await _audioRecorder?.closeRecorder();
      await _audioPlayer?.closePlayer();
      await _audioStreamController?.close();
    } catch (e) {
      log("❌ Error cleaning up audio resources: $e");
    }
    // Stop streaming if active
    if (_isStreaming) {
      _stopVoiceStreaming();
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
    _connectedUsersNotifier.dispose();

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
        log("❌ Error sending leave message: $e");
      }
    }
    print("🧹 [CLEANUP] All resources cleaned up successfully");
  }

  Future<void> _startRobustTcpServer() async {
    int attempt = 0;
    const maxAttempts = 3;

    while (attempt < maxAttempts) {
      try {
        await _startTcpServer();
        break; // Success
      } catch (e) {
        attempt++;
        log("❌ TCP Server attempt $attempt failed: $e");

        if (attempt < maxAttempts) {
          log("🔄 Retrying TCP server in 3 seconds...");
          await Future.delayed(Duration(seconds: 3));

          // Force cleanup sebelum retry
          await _forceCleanupTcpPort();
        } else {
          log("❌ All TCP server attempts failed");
          _showErrorSnackbar(
            'Failed to start TCP server after $maxAttempts attempts',
          );
        }
      }
    }
  }

  Future<void> _forceCleanupTcpPort() async {
    try {
      // Coba close socket dengan berbagai cara
      await _tcpServer?.close();

      // Tunggu OS me-release port
      await Future.delayed(Duration(seconds: 2));

      // Force GC untuk memastikan resources dibersihkan
      await Future(() {});
    } catch (e) {
      log("⚠️ Force cleanup warning: $e");
    }
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
      log("❌ Error loading voice recordings: $e");
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
      log("❌ Error saving voice recording metadata: $e");
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
    log("🎵 [VOICE] Listening for voice recordings on port $VOICE_PORT...");

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
          log("❌ Error processing voice recording from $senderIp: $e");
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
        _showSuccessSnackbar(
          'Voice message received from ${senderIp == _myIpAddress ? 'You' : senderIp}',
        );
      }

      log("🎵 Voice recording saved: $filePath");
    } catch (e) {
      log("❌ Error saving voice recording: $e");
    }
  }

  // Send voice recording to all users
  Future<void> _sendVoiceRecording(String filePath) async {
    try {
      Uint8List audioData = await File(filePath).readAsBytes();
      final usersToSend = List.from(connectedUsers)..remove(_myIpAddress);

      for (String ip in usersToSend) {
        UDP sender = await UDP.bind(Endpoint.any());
        await sender.send(
          audioData,
          Endpoint.unicast(InternetAddress(ip), port: Port(VOICE_PORT)),
        );
        sender.close();
      }

      // await Future.wait(sendFutures, eagerError: false);

      log("🎵 Voice recording sent to ${usersToSend.length} users");
    } catch (e) {
      log("❌ Error sending voice recording: $e");
    }
  }

  // List all voice recordings
  Future<void> _listAllVoiceRecordings() async {
    try {
      if (_voiceRecordings.isEmpty) {
        if (mounted) {
          _showInfoSnackbar('No voice recordings found');
        }
        return;
      }

      showDialog(
        context: context,
        builder: (_) => VoiceHistoryDialog(
          recordings: _voiceRecordings,
          myIp: _myIpAddress,
          onDelete: _deleteVoiceRecording,
        ),
      );
    } catch (e) {
      log("❌ Error listing voice recordings: $e");
    }
  }

  // Delete voice recording
  void _deleteVoiceRecording(VoiceRecording recording, int index) async {
    try {
      await File(recording.filePath).delete();

      setState(() {
        _voiceRecordings.removeAt(index);
      });

      await _saveVoiceRecordingMetadata();

      if (mounted) {
        Navigator.of(context, rootNavigator: true).maybePop();
        _showSuccessSnackbar('Voice recording deleted');
      }
    } catch (e) {
      log("❌ Error deleting voice recording: $e");
      if (mounted) {
        _showErrorSnackbar('Failed to delete voice recording');
      }
    }
  }

  // Format date time for display
  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')} ${dateTime.day}/${dateTime.month}/${dateTime.year}';
  }

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
              int percentage = (progress * 100).toInt();

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
                    SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.grey[300],
                      valueColor: AlwaysStoppedAnimation<Color>(
                        progress < 1.0 ? Colors.blue : Colors.green,
                      ),
                    ),
                    SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '$percentage%',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        Text(
                          '${_getValidTcpClients().length} client(s)',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 4),
                    if (progress < 1.0)
                      Text(
                        'Sending...',
                        style: TextStyle(fontSize: 10, color: Colors.blue),
                      ),
                    if (progress >= 1.0)
                      Text(
                        'Completed!',
                        style: TextStyle(fontSize: 10, color: Colors.green),
                      ),
                  ],
                ),
                actions: [
                  if (progress < 1.0)
                    TextButton(
                      onPressed: () {
                        _isSendingFile = false;
                        Navigator.pop(context);
                        _showInfoSnackbar('Video transfer cancelled');
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

  void _showInfoSnackbar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.blue),
        );
    }
  }

  void _showSuccessSnackbar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.green),
        );
    }
  }

  void _showErrorSnackbar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.red),
        );
    }
  }
}
