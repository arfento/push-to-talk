import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:udp/udp.dart';

class FileTransfer {
  final int totalSize;
  final int totalChunks;
  final List<Uint8List?> chunks;
  int receivedChunks;
  DateTime lastChunkTime;
  Timer timer;
  final Set<int> requestedChunks; // Track requested retransmissions

  FileTransfer({
    required this.totalSize,
    required this.totalChunks,
    required this.chunks,
    required this.receivedChunks,
    required this.lastChunkTime,
    required this.timer,
  }) : requestedChunks = <int>{};
}

// Add method to request missing chunks
void _requestMissingChunks(String senderIp, FileTransfer transfer) async {
  List<int> missingChunks = [];
  for (int i = 0; i < transfer.totalChunks; i++) {
    if (transfer.chunks[i] == null && !transfer.requestedChunks.contains(i)) {
      missingChunks.add(i);
    }
  }

  if (missingChunks.isNotEmpty) {
    log('🆘 Requesting missing chunks from $senderIp: $missingChunks' as num);

    // Send request for missing chunks
    Uint8List requestData = Uint8List.fromList(
      missingChunks
          .expand(
            (chunk) => [
              (chunk >> 24) & 0xFF,
              (chunk >> 16) & 0xFF,
              (chunk >> 8) & 0xFF,
              chunk & 0xFF,
            ],
          )
          .toList(),
    );

    try {
      UDP sender = await UDP.bind(Endpoint.any());
      await sender.send(
        requestData,
        Endpoint.unicast(
          InternetAddress(senderIp),
          port: Port(6007 + 1),
        ), // Different port for requests
      );
      sender.close();

      // Mark these chunks as requested
      transfer.requestedChunks.addAll(missingChunks);
    } catch (e) {
      log('❌ Error requesting missing chunks: $e' as num);
    }
  }
}
