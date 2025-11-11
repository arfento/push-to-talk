import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'package:udp/udp.dart';

class NetworkService {
  static const int discoveryPort = 5000;
  UDP? _udpSender;
  UDP? _udpReceiver;
  StreamSubscription? _udpSubscription;
  Timer? _broadcastTimer;

  // Store active lobbies for validation (in a real app, use a proper database)
  final Map<String, String> _activeLobbies = {}; // lobbyId -> password

  Future<String> startHosting({
    required String lobbyId,
    String password = '',
  }) async {
    _udpSender = await UDP.bind(Endpoint.any());
    _udpReceiver = await UDP.bind(Endpoint.any(port: Port(discoveryPort)));

    String? localIp = await getLocalIp();
    if (localIp == null) {
      throw Exception("Could not determine local IP");
    }

    // Store this lobby in active lobbies
    _activeLobbies[lobbyId] = password;

    print("🔵 [HOST] Hosting Private Lobby...");
    print("🔹 Local IP: $localIp");
    print("🔹 Lobby ID: $lobbyId");
    print("🔹 Password Protected: ${password.isNotEmpty}");
    print("🔹 Broadcasting on port: $discoveryPort");

    // Broadcast lobby availability periodically
    _broadcastTimer = Timer.periodic(Duration(seconds: 2), (timer) async {
      String response =
          "MotoVox_RESPONSE|$localIp|$lobbyId|${password.isNotEmpty ? '1' : '0'}";
      int sentBytes = await _udpSender!.send(
        response.codeUnits,
        Endpoint.broadcast(port: Port(discoveryPort)),
      );
      print("✅ [HOST] Broadcasting lobby: $lobbyId");
    });

    // Listen for discovery requests
    _udpReceiver!.asStream().listen((datagram) {
      if (datagram == null || datagram.data.isEmpty) return;

      String message = String.fromCharCodes(datagram.data);
      String senderIp = datagram.address.address;

      print("📩 [HOST] Received: $message from $senderIp");

      if (message.startsWith("MotoVox_DISCOVER|")) {
        // Parse discovery request
        List<String> parts = message.split('|');
        if (parts.length >= 3) {
          String requestedLobbyId = parts[1];
          String providedPassword = parts.length > 3 ? parts[3] : '';

          // Validate lobby access
          if (_validateLobbyAccess(requestedLobbyId, providedPassword)) {
            print(
              "📡 [HOST] Valid access request for lobby: $requestedLobbyId",
            );
            String response =
                "MotoVox_RESPONSE|$localIp|$lobbyId|${password.isNotEmpty ? '1' : '0'}";
            _udpSender!.send(
              response.codeUnits,
              Endpoint.unicast(
                InternetAddress(senderIp),
                port: Port(discoveryPort),
              ),
            );
          } else {
            print(
              "🚫 [HOST] Invalid access attempt for lobby: $requestedLobbyId",
            );
          }
        }
      }
    });

    return localIp;
  }

  Future<String?> findHost({
    required String lobbyId,
    String password = '',
  }) async {
    _udpReceiver = await UDP.bind(Endpoint.any(port: Port(discoveryPort)));

    print("🔍 [CLIENT] Searching for private lobby: $lobbyId");

    Completer<String?> completer = Completer<String?>();
    Set<String> discoveredHosts = {};
    String? myIp = await getLocalIp();
    print("🟢 [CLIENT] My IP: $myIp");

    String? broadcastIp = await getBroadcastAddress();
    if (broadcastIp == null) {
      print("❌ [CLIENT] Could not determine broadcast address");
      return null;
    }

    print("📢 [CLIENT] Sending discovery for lobby: $lobbyId");

    _udpSubscription = _udpReceiver!.asStream().listen((datagram) {
      if (datagram != null) {
        String message = String.fromCharCodes(datagram.data);
        String senderIp = datagram.address.address;

        if (senderIp == myIp) {
          print("⚠️ [CLIENT] Ignoring own broadcast from $senderIp");
          return;
        }

        print("✅ [CLIENT] Received: $message from $senderIp");

        if (message.startsWith("MotoVox_RESPONSE|")) {
          List<String> parts = message.split('|');
          if (parts.length >= 4) {
            String hostIp = parts[1];
            String responseLobbyId = parts[2];
            bool requiresPassword = parts[3] == '1';

            // Only accept responses for the specific lobby we're looking for
            if (responseLobbyId == lobbyId) {
              print("🎯 [CLIENT] Found our target lobby: $lobbyId");
              discoveredHosts.add(hostIp);
            } else {
              print("🔍 [CLIENT] Ignoring other lobby: $responseLobbyId");
            }
          }
        }
      }
    });

    // Send discovery requests with lobby ID and password
    UDP sender = await UDP.bind(Endpoint.any());

    for (int i = 0; i < 5; i++) {
      String discoveryMessage = "MotoVox_DISCOVER|$lobbyId|$password";
      int sentBytes = await sender.send(
        discoveryMessage.codeUnits,
        Endpoint.broadcast(port: Port(discoveryPort)),
      );
      print(
        "📢 [CLIENT] Sent discovery attempt ${i + 1}/5 for lobby: $lobbyId",
      );
      await Future.delayed(Duration(seconds: 2));
    }

    sender.close();

    return completer.future.timeout(
      Duration(seconds: 12),
      onTimeout: () {
        _udpSubscription?.cancel();
        _udpReceiver?.close();

        if (discoveredHosts.isNotEmpty) {
          String selectedHost = discoveredHosts.first;
          print("✅ [CLIENT] Successfully joined lobby: $lobbyId");
          print("🔗 [CLIENT] Connecting to host: $selectedHost");
          return selectedHost;
        }
        print("❌ Lobby '$lobbyId' not found or invalid credentials");
        return null;
      },
    );
  }

  bool _validateLobbyAccess(String lobbyId, String providedPassword) {
    if (!_activeLobbies.containsKey(lobbyId)) {
      print("🚫 [HOST] Lobby not found: $lobbyId");
      return false;
    }

    String storedPassword = _activeLobbies[lobbyId]!;

    // If lobby has no password, allow access
    if (storedPassword.isEmpty) {
      return true;
    }

    // If lobby has password, validate it
    if (providedPassword == storedPassword) {
      return true;
    } else {
      print("🚫 [HOST] Invalid password for lobby: $lobbyId");
      return false;
    }
  }

  // Generate a random lobby ID
  String generateLobbyId() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    return String.fromCharCodes(
      Iterable.generate(
        6,
        (_) => chars.codeUnitAt(random.nextInt(chars.length)),
      ),
    );
  }

  // Remove lobby when host disconnects
  void removeLobby(String lobbyId) {
    _activeLobbies.remove(lobbyId);
    _broadcastTimer?.cancel();
    print("🗑️ [HOST] Removed lobby: $lobbyId");
  }

  Future<String?> getBroadcastAddress() async {
    for (var interface in await NetworkInterface.list()) {
      for (var addr in interface.addresses) {
        if (addr.type == InternetAddressType.IPv4 &&
            (addr.address.startsWith("172.16.") ||
                addr.address.startsWith("192.168."))) {
          List<String> parts = addr.address.split('.');
          if (parts.length == 4) {
            String broadcastIp = "${parts[0]}.${parts[1]}.${parts[2]}.255";
            return broadcastIp;
          }
        }
      }
    }
    return null;
  }

  Future<String?> getLocalIp() async {
    for (var interface in await NetworkInterface.list()) {
      for (var addr in interface.addresses) {
        if (addr.type == InternetAddressType.IPv4 &&
            (addr.address.startsWith("172.16.") ||
                addr.address.startsWith("192.168."))) {
          return addr.address;
        }
      }
    }
    return null;
  }

  void dispose() {
    _broadcastTimer?.cancel();
    _udpSender?.close();
    _udpReceiver?.close();
    _udpSubscription?.cancel();
    _activeLobbies.clear();
  }
}
