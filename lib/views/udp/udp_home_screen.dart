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

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF11E0DC), // MotoVox theme color
              Color(0xFFFF6767), // Complementary gradient color
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                LucideIcons.radio, // Use a walkie-talkie style icon
                size: 100,
                color: Colors.white,
              ),
              const SizedBox(height: 16),

              const SizedBox(height: 8),

              // Subtitle
              Text(
                'Walkie-Talkie for Groups',
                style: TextStyle(fontSize: 18, color: Colors.white70),
              ),

              const SizedBox(height: 40),

              // Create Lobby Button
              _buildButton(
                context,
                icon: LucideIcons.plusCircle,
                label: 'Create Lobby',
                isLoading: _isCreatingLobby,
                onTap: _createLobby,
              ),

              const SizedBox(height: 20),

              // Join Lobby Button
              _buildButton(
                context,
                icon: LucideIcons.radioTower,
                label: 'Join Lobby',
                isLoading: _isJoiningLobby,
                onTap: _joinLobby,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createLobby() async {
    if (_isCreatingLobby) return;

    setState(() => _isCreatingLobby = true);

    try {
      String hostIp = await networkService.startHosting();
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => LobbyScreen(isHost: true, hostIp: hostIp),
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
      String? hostAddress = await networkService.findHost();

      if (mounted) {
        Navigator.pop(context); // Close loading dialog

        if (hostAddress != null) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  LobbyScreen(isHost: false, hostIp: hostAddress),
            ),
          );
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("No lobbies found.")));
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

  // Custom Button Widget
  // Updated button with loading state
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
                      "Searching for lobbies...",
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
