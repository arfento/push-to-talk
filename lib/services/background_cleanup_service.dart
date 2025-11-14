import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:udp/udp.dart';

class BackgroundCleanupService {
  static bool _isInitialized = false;

  static Future<void> initialize() async {
    if (_isInitialized) return;

    final service = FlutterBackgroundService();

    await service.configure(
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onStart,
        // onBackground: onStart,
      ),
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: true,
        isForegroundMode: false,
      ),
    );

    _isInitialized = true;
  }

  static Future<void> notifyUserLeft(
    String hostIp,
    bool isHost,
    String myIp,
    List<String> connectedUsers,
  ) async {
    try {
      final service = FlutterBackgroundService();

      if (await service.isRunning()) {
        service.invoke('userLeft', {
          'hostIp': hostIp,
          'isHost': isHost,
          'myIp': myIp,
          'connectedUsers': connectedUsers,
        });
        print("📤 [BACKGROUND] Sent leave notification request");
      } else {
        // Jika service tidak running, kirim langsung
        await _sendLeaveNotification(hostIp, isHost, myIp, connectedUsers);
      }
    } catch (e) {
      print("❌ [BACKGROUND] Error in notifyUserLeft: $e");
      // Fallback: kirim langsung
      await _sendLeaveNotification(hostIp, isHost, myIp, connectedUsers);
    }
  }

  static Future<void> onStart(ServiceInstance service) async {
    print("🔄 [BACKGROUND] Background service started");

    service.on('userLeft').listen((event) async {
      print("🔄 [BACKGROUND] Processing userLeft event");

      final hostIp = event?['hostIp'] as String?;
      final isHost = event?['isHost'] as bool? ?? false;
      final myIp = event?['myIp'] as String?;
      final connectedUsers = List<String>.from(event?['connectedUsers'] ?? []);

      if (hostIp != null && myIp != null) {
        await _sendLeaveNotification(hostIp, isHost, myIp, connectedUsers);
      }

      // Stop service setelah selesai
      await service.stopSelf();
      print("🛑 [BACKGROUND] Background service stopped");
    });
  }

  static Future<void> _sendLeaveNotification(
    String hostIp,
    bool isHost,
    String myIp,
    List<String> connectedUsers,
  ) async {
    try {
      print("📤 [BACKGROUND] Sending leave notification...");
      print("📤 [BACKGROUND] Host IP: $hostIp, Is Host: $isHost, My IP: $myIp");

      if (!isHost && hostIp.isNotEmpty) {
        // Client mengirim LEAVE ke host
        UDP sender = await UDP.bind(Endpoint.any());
        await sender.send(
          Uint8List.fromList("LEAVE".codeUnits),
          Endpoint.unicast(InternetAddress(hostIp), port: Port(6002)),
        );
        sender.close();
        print("📤 [BACKGROUND] Client sent LEAVE to host: $hostIp");
      } else if (isHost) {
        // Host mengirim HOST_LEAVING ke semua client
        for (String ip in connectedUsers) {
          if (ip != myIp) {
            try {
              UDP sender = await UDP.bind(Endpoint.any());
              await sender.send(
                Uint8List.fromList("HOST_LEAVING".codeUnits),
                Endpoint.unicast(InternetAddress(ip), port: Port(6003)),
              );
              sender.close();
              print("📤 [BACKGROUND] Host sent HOST_LEAVING to client: $ip");
            } catch (e) {
              print("❌ [BACKGROUND] Error notifying client $ip: $e");
            }
          }
        }
      }

      print("✅ [BACKGROUND] Leave notifications sent successfully");
    } catch (e) {
      print("❌ [BACKGROUND] Error sending leave notification: $e");
    }
  }
}
