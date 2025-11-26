import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:push_to_talk_app/core/services/signaling.dart';
import 'package:push_to_talk_app/presentation/pages/video_call/components/video_render_view.dart';

class WebRTCBody extends StatelessWidget {
  final bool localRenderOk;
  final Map<String, RTCVideoRenderer> remoteRenderers;
  final Map<String, bool?> remoteRenderersLoading;
  final RTCVideoRenderer localRenderer;
  final TextEditingController controller;
  final Signaling signaling;
  final bool isInitiator;

  const WebRTCBody({
    super.key,
    required this.localRenderOk,
    required this.remoteRenderers,
    required this.remoteRenderersLoading,
    required this.localRenderer,
    required this.controller,
    required this.signaling,
    this.isInitiator = false, // Default false
  });

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).size.width > MediaQuery.of(context).size.height;

    return Stack(
      children: [
        Container(
          margin: const EdgeInsets.all(8.0),
          child: Column(
            children: [
              // Streaming views
              Expanded(
                child: isLandscape
                    ? Row(children: _buildVideoViews())
                    : Column(children: _buildVideoViews()),
              ),
            ],
          ),
        ),

        // Status message overlay
        Positioned(top: 20, left: 0, right: 0, child: _buildStatusIndicator()),
      ],
    );
  }

  Widget _buildStatusIndicator() {
    // Jika sudah terhubung, tidak perlu tampilkan status
    if (signaling.isJoined()) {
      return const SizedBox.shrink();
    }

    String statusMessage = "";
    Color statusColor = Colors.transparent;

    if (isInitiator) {
      // Caller (initiator)
      if (!localRenderOk) {
        statusMessage = "Preparing camera...";
        statusColor = Colors.orange;
      } else {
        statusMessage = "Starting call...";
        statusColor = Colors.blue;
      }
    } else {
      // Callee (penerima)
      if (!localRenderOk) {
        statusMessage = "Incoming call... Preparing camera";
        statusColor = Colors.orange;
      } else {
        statusMessage = "Incoming call... Tap start to join";
        statusColor = Colors.green;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.9),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isInitiator && localRenderOk)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
          if (isInitiator && localRenderOk) const SizedBox(width: 8),
          Text(
            statusMessage,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  List<Widget> _buildVideoViews() {
    final List<Widget> views = [];

    if (localRenderOk) {
      views.add(
        VideoRendererView(
          renderer: localRenderer,
          loading: false,
          mirror: !signaling.isScreenSharing(),
        ),
      );
    }

    for (final entry in remoteRenderers.entries) {
      views.add(
        VideoRendererView(
          renderer: entry.value,
          loading: remoteRenderersLoading[entry.key] ?? true,
        ),
      );
    }

    // Jika tidak ada video yang ditampilkan, tampilkan placeholder
    if (views.isEmpty) {
      views.add(
        Container(
          color: Colors.black,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.videocam_off, size: 64, color: Colors.grey[600]),
                const SizedBox(height: 16),
                Text(
                  isInitiator ? "Starting call..." : "Waiting to join call...",
                  style: TextStyle(color: Colors.grey[600], fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return views;
  }
}
