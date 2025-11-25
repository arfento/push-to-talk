import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:udp/udp.dart';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class BackgroundCleanupService {
  static bool _isInitialized = false;

  static Future<void> initialize() async {
    if (_isInitialized) return;

    final service = FlutterBackgroundService();

    await service.configure(
      iosConfiguration: IosConfiguration(
        autoStart: false, // Don't auto-start on iOS
        onForeground: onStart,
      ),
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true, // Changed to true
        notificationChannelId: 'walkie_cleanup_channel',
        initialNotificationTitle: 'Walkie-Talkie Cleanup',
        initialNotificationContent: 'Monitoring connections',
        foregroundServiceNotificationId: 888,
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

      // if (await service.isRunning()) {
      //   service.invoke('userLeft', {
      //     'hostIp': hostIp,
      //     'isHost': isHost,
      //     'myIp': myIp,
      //     'connectedUsers': connectedUsers,
      //   });
      //   print("📤 [BACKGROUND] Sent leave notification request");
      // } else {
      //   // Jika service tidak running, kirim langsung
      await _sendLeaveNotification(hostIp, isHost, myIp, connectedUsers);
      // }
    } catch (e) {
      print("❌ [BACKGROUND] Error in notifyUserLeft: $e");
      // Fallback: kirim langsung
      await _sendLeaveNotification(hostIp, isHost, myIp, connectedUsers);
    }
  }

  // static Future<void> onStart(ServiceInstance service) async {
  //   print("🔄 [BACKGROUND] Background service started");

  //   service.on('userLeft').listen((event) async {
  //     print("🔄 [BACKGROUND] Processing userLeft event");

  //     final hostIp = event?['hostIp'] as String?;
  //     final isHost = event?['isHost'] as bool? ?? false;
  //     final myIp = event?['myIp'] as String?;
  //     final connectedUsers = List<String>.from(event?['connectedUsers'] ?? []);

  //     if (hostIp != null && myIp != null) {
  //       await _sendLeaveNotification(hostIp, isHost, myIp, connectedUsers);
  //     }

  //     // Stop service setelah selesai
  //     await service.stopSelf();
  //     print("🛑 [BACKGROUND] Background service stopped");
  //   });
  // }

  static Future<void> onStart(ServiceInstance service) async {
    print("🔄 [BACKGROUND] Background service started");

    // Listen for stop command
    service.on("stopService").listen((event) async {
      print("🛑 [BACKGROUND] Received stop command");
      await service.stopSelf();
    });

    // If you're using foreground mode on Android
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: "Walkie-Talkie Cleanup",
        content: "Monitoring connections",
      );
    }

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

  Future<void> initializeService() async {
    final service = FlutterBackgroundService();

    /// OPTIONAL, using custom notification channel id
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'my_foreground', // id
      'MY FOREGROUND SERVICE', // title
      description:
          'This channel is used for important notifications.', // description
      importance: Importance.low, // importance must be at low or higher level
    );

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    if (Platform.isIOS || Platform.isAndroid) {
      await flutterLocalNotificationsPlugin.initialize(
        const InitializationSettings(
          iOS: DarwinInitializationSettings(),
          android: AndroidInitializationSettings('ic_bg_service_small'),
        ),
      );
    }

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        // this will be executed when app is in foreground or background in separated isolate
        onStart: onStart,

        // auto start service
        autoStart: true,
        isForegroundMode: true,

        notificationChannelId: 'my_foreground',
        initialNotificationTitle: 'AWESOME SERVICE',
        initialNotificationContent: 'Initializing',
        foregroundServiceNotificationId: 888,
        foregroundServiceTypes: [AndroidForegroundType.location],
      ),
      iosConfiguration: IosConfiguration(
        // auto start service
        autoStart: true,

        // this will be executed when app is in foreground in separated isolate
        onForeground: onStart,

        // you have to enable background fetch capability on xcode project
        // onBackground: onIosBackground,
      ),
    );
  }
}
