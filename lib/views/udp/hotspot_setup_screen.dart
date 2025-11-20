import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class HotspotSetupScreen extends StatelessWidget {
  Future<void> openHotspotSettings() async {
    // Opens the hotspot settings page on Android
    const url = 'android.settings.TETHER_SETTINGS';
    try {
      await launch('intent://$url#Intent;scheme=android-app;end;');
    } catch (e) {
      print('Could not open hotspot settings: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Setup Hotspot")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("Please enable your Mobile Hotspot manually."),
            SizedBox(height: 10),
            ElevatedButton(
              onPressed: openHotspotSettings,
              child: Text("Open Hotspot Settings"),
            ),
            SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}
