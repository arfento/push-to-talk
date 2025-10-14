import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:push_to_talk_app/bloc/camera_bloc.dart';
import 'package:push_to_talk_app/utils/camera_utils.dart';
import 'package:push_to_talk_app/utils/permission_utils.dart';
import 'package:push_to_talk_app/views/udp/file_transfer.dart';
import 'package:push_to_talk_app/views/video_stream/pages/camera_page.dart';
import 'package:push_to_talk_app/views/video_stream/widgets/video_path_dialog.dart';
import 'package:udp/udp.dart';
import 'package:flutter_sound/flutter_sound.dart';

class LobbyScreen extends StatefulWidget {
  static const String id = 'lobby_screen';
  final bool isHost;
  final String hostIp; // Host's IP

  const LobbyScreen({super.key, required this.isHost, required this.hostIp});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
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

  //send & received message
  TextEditingController messageController = TextEditingController();
  List<String> messages = []; // Stores received messages

  @override
  void initState() {
    super.initState();
    // voiceService.init();
    // voiceService.targetIp = widget.hostIp;
    getLocalIp();
    _audioRecorder = FlutterSoundRecorder();
    _audioPlayer = FlutterSoundPlayer();
    _initAudio();

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

  Future<void> _initAudio() async {
    await _audioRecorder!.openRecorder();
    await _audioPlayer!.openPlayer();
    await _startPlayerForStream(); // Initial setup
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
      await _audioPlayer!.startPlayerFromStream(
        codec: Codec.pcm16,
        numChannels: 2,
        sampleRate: Platform.isIOS ? 44100 : 16000,
        // sampleRate: 48000,
        interleaved: true,
        bufferSize: 1024,
      );

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
      // sampleRate: 48000,
      sampleRate: Platform.isIOS ? 44100 : 16000,
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

            // Validate data before processing
            if (audioData.length % 2 != 0) {
              print(
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
              await _stopPlayerForStream();
              _silenceTimer?.cancel();
              return;
            }

            // Process valid audio data
            await _processAudioData(audioData);
          }
        },
        onError: (error) {
          print("❌ [AUDIO] UDP reception error: $error");
        },
      );
    } catch (e) {
      print("❌ [AUDIO] Error binding UDP socket: $e");
    }
  }

  Future<void> _processAudioData(Uint8List audioData) async {
    try {
      await _startPlayerForStream();

      _silenceTimer?.cancel();
      _silenceTimer = Timer(Duration(milliseconds: 500), () async {
        await _stopPlayerForStream();
        print("🔇 [CLIENT] No audio for 500ms, stopping player...");
      });

      print("📥 Received audio chunk size: ${audioData.length}");

      await _audioPlayer!.feedUint8FromStream(audioData);
    } catch (e) {
      print("❌ [AUDIO] Error processing audio: $e");
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
    log("🔄 [CLIENT] Listening for user list updates on port 6003...");

    receiver.asStream().listen(
      (datagram) {
        if (datagram != null && datagram.data.isNotEmpty) {
          String receivedData = String.fromCharCodes(datagram.data);
          List<String> updatedUsers = receivedData.split(',');
          log("receivedData $receivedData");

          if (receivedData.contains(',') ||
              RegExp(r'^(\d{1,3}\.){3}\d{1,3}$').hasMatch(receivedData)) {
            List<String> updatedUsers = receivedData.split(',');
            log("🔄 [CLIENT] Received updated user list: $updatedUsers");

            setState(() {
              connectedUsers = updatedUsers;
            });
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

      _tcpServer!.listen((Socket client) {
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

    // Show progress dialog
    _showFileTransferProgressDialog();

    try {
      Uint8List videoData = await videoFile.readAsBytes();
      String fileName = 'video_${DateTime.now().millisecondsSinceEpoch}.mp4';
      log('sendvideo _listenForVideoStream _sendVideoFileOverTCP $fileName');

      // Create header: [fileSize:4bytes][fileNameLength:4bytes][fileName]
      Uint8List fileNameBytes = Uint8List.fromList(fileName.codeUnits);
      Uint8List header = Uint8List(8 + fileNameBytes.length);
      ByteData headerData = ByteData.view(header.buffer);
      headerData.setUint32(0, videoData.length, Endian.big);
      headerData.setUint32(4, fileNameBytes.length, Endian.big);
      header.setRange(8, 8 + fileNameBytes.length, fileNameBytes);

      // Send header + file data
      List<Socket> clients = List.from(_tcpClients);
      int totalClients = clients.length;
      int successfulSends = 0;

      for (int i = 0; i < clients.length; i++) {
        Socket client = clients[i];
        try {
          // Simple check - try to get the remote address
          await client.remoteAddress;

          // Update progress for client connection
          _updateFileTransferProgress(
            (i / totalClients) * 0.1, // 10% for connections
            'Connecting to client ${i + 1}/$totalClients',
          );

          client.add(header);
          client.add(videoData);
          await client.flush();

          successfulSends++;
          log("sendvideo 📤 [TCP] Video file sent to client: $fileName");

          // Update progress for successful send
          _updateFileTransferProgress(
            0.1 +
                (successfulSends / totalClients) *
                    0.9, // Remaining 90% for data transfer
            'Sent to $successfulSends/$totalClients clients',
          );
        } catch (e) {
          log("sendvideo ❌ [TCP] Client error, removing: $e");
          _tcpClients.remove(client);
        }
      }
      // Final progress update
      _updateFileTransferProgress(1.0, 'Transfer completed');

      await Future.delayed(
        Duration(milliseconds: 500),
      ); // Show completion briefly

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
                                "${messages[index]}",
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // list _listAllVideos
                      IconButton(
                        onPressed: _listAllVideos,
                        icon: Icon(
                          Icons.file_download_rounded,
                          size: 36,
                          color: Colors.blueAccent,
                        ),
                        tooltip: 'List file recording',
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.grey[200],
                          padding: EdgeInsets.all(12),
                          shape: CircleBorder(),
                          shadowColor: Colors.black.withOpacity(0.2),
                          elevation: 4,
                        ),
                      ),
                      SizedBox(width: 16),

                      // Video Recording Button
                      IconButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => BlocProvider(
                                create: (context) {
                                  return CameraBloc(
                                    cameraUtils: CameraUtils(),
                                    permissionUtils: PermissionUtils(),
                                  )..add(
                                    const CameraInitialize(recordingLimit: 15),
                                  );
                                },
                                child: CameraPage(
                                  onVideoRecorded: (String videoPath) async {
                                    // Handle the recorded video path here
                                    print(
                                      'sendvideo Video recorded at: $videoPath',
                                    );

                                    // Create XFile from path
                                    XFile xFile = XFile(videoPath);
                                    await _sendVideoFileOverTCP(xFile);

                                    // You can navigate to another screen, upload the video, etc.
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                        icon: Icon(
                          Icons.videocam,
                          size: 36,
                          color: Colors.blueAccent,
                        ),
                        tooltip: 'Record Video',
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
                      // Recording Button
                      IconButton(
                        onPressed: () async {
                          if (_isRecording) {
                            _stopRecording();
                          } else {
                            if (await PermissionUtils()
                                .getCameraAndMicrophonePermissionStatus()) {
                              _startRecording();
                            } else {
                              if (await PermissionUtils().askForPermission()) {
                                _startRecording();
                              } else {
                                log("Permission is denied");
                                return Future.error(
                                  "Permission is denied",
                                ); // Throw the specific error type for permission denial
                              }
                            }
                          }
                        },
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
                        onPressed: () async {
                          if (_isStreaming) {
                            _stopStreaming();
                          } else {
                            if (await PermissionUtils()
                                .getCameraAndMicrophonePermissionStatus()) {
                              _startStreaming();
                            } else {
                              if (await PermissionUtils().askForPermission()) {
                                _startStreaming();
                              } else {
                                log("Permission is denied");
                                return Future.error(
                                  "Permission is denied",
                                ); // Throw the specific error type for permission denial
                              }
                            }
                          }
                        },

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
    udpSocket?.close();
    _audioRecorder?.closeRecorder();
    _audioPlayer?.closePlayer();
    _audioStreamController?.close();

    for (Socket client in _tcpClients) {
      client.destroy();
    }
    _tcpServer?.close();
    super.dispose();
  }

  // Show file transfer progress dialog
  void _showFileTransferProgressDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(
              child: Text('Sending Video File', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _currentFileName,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: 16),
            LinearProgressIndicator(
              value: _fileTransferProgress,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
            ),
            SizedBox(height: 8),
            Text(
              '${(_fileTransferProgress * 100).toStringAsFixed(1)}%',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        actions: [
          if (_fileTransferProgress < 1.0)
            TextButton(
              onPressed: () {
                // Option to cancel transfer
                _isSendingFile = false;
                Navigator.pop(context);
              },
              child: Text('Cancel'),
            ),
        ],
      ),
    );
  }

  // Hide file transfer progress dialog
  void _hideFileTransferProgressDialog() {
    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  // Update file transfer progress
  void _updateFileTransferProgress(double progress, String fileName) {
    if (mounted) {
      setState(() {
        _fileTransferProgress = progress;
        _currentFileName = fileName;
      });
    }
  }
}
