import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:push_to_talk_app/services/network_service.dart';
import 'package:push_to_talk_app/views/udp/stream_voice.dart';

import 'lobby_screen.dart';

class UdpHomeScreen extends StatelessWidget {
  final NetworkService networkService = NetworkService();

  UdpHomeScreen({super.key});

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
              const Spacer(),

              // MotoVox Logo or Icon
              Icon(
                LucideIcons.radio, // Use a walkie-talkie style icon
                size: 100,
                color: Colors.white,
              ),
              const SizedBox(height: 16),

              // Title
              // Text(
              //   'Jabberry',
              //   style: TextStyle(
              //     fontSize: 36,
              //     fontWeight: FontWeight.bold,
              //     color: Colors.white,
              //     letterSpacing: 1.5,
              //   ),
              // ),
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
                onTap: () async {
                  String hostIp = await networkService.startHosting();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          LobbyScreen(isHost: true, hostIp: hostIp),
                    ),
                  );
                },
              ),

              const SizedBox(height: 20),

              // Join Lobby Button
              _buildButton(
                context,
                icon: LucideIcons.radioTower,
                label: 'Join Lobby',
                onTap: () async {
                  _showLoadingDialog(context); // Show loading dialog

                  String? hostAddress = await networkService.findHost();

                  // Dismiss loading dialog
                  Navigator.pop(context);

                  if (hostAddress != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            LobbyScreen(isHost: false, hostIp: hostAddress),
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("No lobbies found.")),
                    );
                  }
                },
              ),

              const Spacer(),

              _buildButton(
                context,
                icon: LucideIcons.radioTower,
                label: 'Stream Example',
                onTap: () async {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => StreamsExample()),
                  );
                },
              ),

              // // Bottom Tagline
              // Padding(
              //   padding: const EdgeInsets.only(bottom: 20),
              //   child: Text(
              //     'Stay in sync with your crew 😎',
              //     style: TextStyle(fontSize: 16, color: Colors.white70),
              //   ),
              // ),
            ],
          ),
        ),
      ),
    );
  }

  // Custom Button Widget
  Widget _buildButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
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
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
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
      barrierDismissible: false, // Prevent closing by tapping outside
      builder: (BuildContext context) {
        return Stack(
          children: [
            // Blurred background
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
              child: Container(color: Colors.black.withOpacity(0.2)),
            ),
            Center(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.transparent,
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
                    const CircularProgressIndicator(color: Color(0xFF11E0DC)),
                    const SizedBox(height: 16),
                    // const Text(
                    //   "Searching for lobbies...",
                    //   style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    // ),
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
