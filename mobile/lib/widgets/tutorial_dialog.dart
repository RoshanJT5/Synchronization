import 'package:flutter/material.dart';

class TutorialDialog extends StatelessWidget {
  const TutorialDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('How Synchronization Works'),
      content: const SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome to Synchronization! Here is a quick guide to getting the best experience:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            Text(
              '• Connecting to the Extension: Open the Synchronization extension in your browser, start hosting, and scan the QR code from this app to receive audio.',
            ),
            SizedBox(height: 8),
            Text(
              '• App-to-App Connection: You can also host audio directly from your phone and let other phones connect to it!',
            ),
            SizedBox(height: 8),
            Text(
              '• Best Performance: For the smoothest experience, ensure all devices are connected to the same WiFi network or hotspot.',
            ),
            SizedBox(height: 8),
            Text(
              '• The 0.7-Second Delay: To ensure all receiving phones play perfectly in sync with each other, the host extension delays the audio sent to the phones by about 0.7 seconds. This means the computer and the phones won\'t be 100% in sync locally, but all phones will be perfectly synced together!',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Got it!'),
        ),
      ],
    );
  }
}
