import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:push_to_talk_app/services/network_service.dart';
import 'package:push_to_talk_app/views/udp/stream_voice.dart';

import 'lobby_screen.dart';

class UdpHomeScreen extends StatefulWidget {
  static const String id = 'udp_home_screen';

  UdpHomeScreen({super.key});

  @override
  State<UdpHomeScreen> createState() => _UdpHomeScreenState();
}

class _UdpHomeScreenState extends State<UdpHomeScreen> {
  final NetworkService networkService = NetworkService();

  List<CameraDescription>? _cameras;
  bool _isLoadingCameras = false;

  @override
  void initState() {
    super.initState();
    _initializeCameras();
  }

  Future<void> _initializeCameras() async {
    setState(() {
      _isLoadingCameras = true;
    });

    try {
      // Ensure camera permissions are granted
      var cameraStatus = await Permission.camera.status;
      if (cameraStatus != PermissionStatus.granted) {
        cameraStatus = await Permission.camera.request();
      }

      var microphoneStatus = await Permission.microphone.status;
      if (microphoneStatus != PermissionStatus.granted) {
        microphoneStatus = await Permission.microphone.request();
      }

      if (cameraStatus == PermissionStatus.granted &&
          microphoneStatus == PermissionStatus.granted) {
        // Get available cameras
        _cameras = await availableCameras();
      } else {
        // Handle permission denied
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Camera and microphone permissions are required'),
            ),
          );
        }
      }
    } catch (e) {
      print('Error initializing cameras: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to initialize camera')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingCameras = false;
        });
      }
    }
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
                isLoading: _isLoadingCameras,
                onTap: _cameras == null || _cameras!.isEmpty
                    ? null
                    : () async {
                        String hostIp = await networkService.startHosting();
                        if (mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => LobbyScreen(
                                isHost: true,
                                hostIp: hostIp,
                                cameras: _cameras!,
                              ),
                            ),
                          );
                        }
                      },
              ),

              const SizedBox(height: 20),

              // Join Lobby Button
              _buildButton(
                context,
                icon: LucideIcons.radioTower,
                label: 'Join Lobby',
                isLoading: _isLoadingCameras,
                onTap: _cameras == null || _cameras!.isEmpty
                    ? null
                    : () async {
                        _showLoadingDialog(context); // Show loading dialog

                        String? hostAddress = await networkService.findHost();

                        // Dismiss loading dialog
                        if (mounted) {
                          Navigator.pop(context);
                        }

                        if (hostAddress != null && mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => LobbyScreen(
                                isHost: false,
                                hostIp: hostAddress,
                                cameras: _cameras!,
                              ),
                            ),
                          );
                        } else if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("No lobbies found.")),
                          );
                        }
                      },
              ),

              const Spacer(),

              // _buildButton(
              //   context,
              //   icon: LucideIcons.radioTower,
              //   label: 'Stream Example',
              //   onTap: () async {
              //     Navigator.push(
              //       context,
              //       MaterialPageRoute(builder: (context) => StreamsExample()),
              //     );
              //   },
              // ),

              // // Bottom Tagline
              // Padding(
              //   padding: const EdgeInsets.only(bottom: 20),
              //   child: Text(
              //     'Stay in sync with your crew 😎',
              //     style: TextStyle(fontSize: 16, color: Colors.white70),
              //   ),
              // ),

              // Show camera status
              if (_isLoadingCameras)
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Column(
                    children: [
                      const CircularProgressIndicator(color: Colors.white),
                      const SizedBox(height: 10),
                      Text(
                        'Initializing camera...',
                        style: TextStyle(fontSize: 14, color: Colors.white70),
                      ),
                    ],
                  ),
                )
              else if (_cameras == null || _cameras!.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Column(
                    children: [
                      Icon(
                        LucideIcons.cameraOff,
                        size: 40,
                        color: Colors.white54,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Camera not available',
                        style: TextStyle(fontSize: 14, color: Colors.white70),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: _initializeCameras,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white.withOpacity(0.2),
                          foregroundColor: Colors.white,
                        ),
                        child: Text('Retry'),
                      ),
                    ],
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Text(
                    '${_cameras!.length} camera(s) ready',
                    style: TextStyle(fontSize: 14, color: Colors.white70),
                  ),
                ),
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
    required VoidCallback? onTap,
    required bool isLoading,
  }) {
    final isDisabled = onTap == null || isLoading;

    return InkWell(
      onTap: isDisabled ? null : onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: isDisabled
              ? Colors.white.withOpacity(0.08)
              : Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDisabled
                ? Colors.white.withOpacity(0.1)
                : Colors.white.withOpacity(0.3),
          ),
          boxShadow: isDisabled
              ? []
              : [
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
                  color: Colors.white,
                ),
              )
            else
              Icon(
                icon,
                color: isDisabled ? Colors.white54 : Colors.white,
                size: 24,
              ),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDisabled ? Colors.white54 : Colors.white,
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
                    const Text(
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
