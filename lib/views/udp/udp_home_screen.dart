import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:push_to_talk_app/services/network_service.dart';

import 'lobby_screen.dart';

class UdpHomeScreen extends StatefulWidget {
  static const String id = 'udp_home_screen';

  UdpHomeScreen({super.key});

  @override
  State<UdpHomeScreen> createState() => _UdpHomeScreenState();
}

class _UdpHomeScreenState extends State<UdpHomeScreen> {
  final NetworkService networkService = NetworkService();
  bool _isCreatingLobby = false;
  bool _isJoiningLobby = false;

  // Controllers for input fields
  final TextEditingController _lobbyIdController = TextEditingController();
  // final TextEditingController _passwordController = TextEditingController();

  // For creating lobby
  final TextEditingController _createLobbyIdController =
      TextEditingController();
  // final TextEditingController _createPasswordController =
  //     TextEditingController();

  @override
  void initState() {
    super.initState();
    // Generate a random lobby ID suggestion
    _createLobbyIdController.text = _generateLobbyId();
  }

  @override
  void dispose() {
    _lobbyIdController.dispose();
    // _passwordController.dispose();
    _createLobbyIdController.dispose();
    // _createPasswordController.dispose();
    super.dispose();
  }

  String _generateLobbyId() {
    // Generate a 6-character alphanumeric ID
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    return String.fromCharCodes(
      Iterable.generate(
        6,
        (_) => chars.codeUnitAt(random.nextInt(chars.length)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF11E0DC), Color(0xFFFF6767)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.radio, size: 100, color: Colors.white),
              const SizedBox(height: 16),
              Text(
                'Walkie-Talkie for Groups',
                style: TextStyle(fontSize: 18, color: Colors.white70),
              ),
              const SizedBox(height: 40),

              // Create Lobby Button
              _buildButton(
                context,
                icon: LucideIcons.plusCircle,
                label: 'Create Private Lobby',
                isLoading: _isCreatingLobby,
                onTap: _showCreateLobbyDialog,
              ),
              const SizedBox(height: 20),

              // Join Lobby Button
              _buildButton(
                context,
                icon: LucideIcons.radioTower,
                label: 'Join Private Lobby',
                isLoading: _isJoiningLobby,
                onTap: _showJoinLobbyDialog,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCreateLobbyDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Create Private Lobby"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _createLobbyIdController,
              decoration: InputDecoration(
                labelText: "Lobby ID",
                hintText: "Enter unique lobby ID",
                border: OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(Icons.refresh),
                  onPressed: () {
                    _createLobbyIdController.text = _generateLobbyId();
                  },
                ),
              ),
            ),
            // SizedBox(height: 16),
            // TextField(
            //   controller: _createPasswordController,
            //   decoration: InputDecoration(
            //     labelText: "Password (Optional)",
            //     hintText: "Set a password for extra security",
            //     border: OutlineInputBorder(),
            //   ),
            //   obscureText: true,
            // ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _createLobby();
            },
            child: Text("Create Lobby"),
          ),
        ],
      ),
    );
  }

  void _showJoinLobbyDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Join Private Lobby"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _lobbyIdController,
              decoration: InputDecoration(
                labelText: "Lobby ID",
                hintText: "Enter lobby ID",
                border: OutlineInputBorder(),
              ),
            ),
            // SizedBox(height: 16),
            // TextField(
            //   controller: _passwordController,
            //   decoration: InputDecoration(
            //     labelText: "Password",
            //     hintText: "Enter lobby password",
            //     border: OutlineInputBorder(),
            //   ),
            //   obscureText: true,
            // ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _joinLobby();
            },
            child: Text("Join Lobby"),
          ),
        ],
      ),
    );
  }

  Future<void> _createLobby() async {
    if (_isCreatingLobby) return;

    setState(() => _isCreatingLobby = true);

    try {
      String lobbyId = _createLobbyIdController.text.trim();
      // String password = _createPasswordController.text.trim();

      if (lobbyId.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Please enter a lobby ID")));
        return;
      }

      String hostIp = await networkService.startHosting(
        lobbyId: lobbyId,
        // password: password,
      );

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) =>
                LobbyScreen(isHost: true, hostIp: hostIp, lobbyId: lobbyId),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Failed to create lobby: $e")));
      }
    } finally {
      if (mounted) {
        setState(() => _isCreatingLobby = false);
      }
    }
  }

  Future<void> _joinLobby() async {
    if (_isJoiningLobby) return;

    setState(() => _isJoiningLobby = true);
    _showLoadingDialog(context);

    try {
      String lobbyId = _lobbyIdController.text.trim();
      // String password = _passwordController.text.trim();

      if (lobbyId.isEmpty) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text("Please enter a lobby ID")));
        }
        return;
      }

      String? hostAddress = await networkService.findHost(
        lobbyId: lobbyId,
        // password: password,
      );

      if (mounted) {
        Navigator.pop(context); // Close loading dialog

        if (hostAddress != null) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => LobbyScreen(
                isHost: false,
                hostIp: hostAddress,
                lobbyId: lobbyId,
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Lobby not found or invalid credentials")),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Failed to join lobby: $e")));
      }
    } finally {
      if (mounted) {
        setState(() => _isJoiningLobby = false);
      }
    }
  }

  // Custom Button Widget (unchanged)
  Widget _buildButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool isLoading = false,
  }) {
    return InkWell(
      onTap: isLoading ? null : onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(isLoading ? 0.1 : 0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              offset: const Offset(0, 4),
              blurRadius: 8,
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            else
              Icon(icon, color: Colors.white, size: 24),
            const SizedBox(width: 10),
            Text(
              isLoading ? "Please wait..." : label,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLoadingDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Stack(
          children: [
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
              child: Container(color: Colors.black.withOpacity(0.2)),
            ),
            Center(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Color(0xFF11E0DC)),
                    const SizedBox(height: 16),
                    Text(
                      "Joining lobby...",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
