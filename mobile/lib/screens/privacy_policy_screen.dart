import 'package:flutter/material.dart';
import 'package:synchronization/theme/app_theme.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: const Text('Privacy Policy'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppTheme.surface, AppTheme.bg],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
          children: [
            // ── Badge ──
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.accent.withOpacity(0.6)),
                ),
                child: const Text(
                  'PRIVACY POLICY',
                  style: TextStyle(
                    color: AppTheme.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Private by Design.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 30,
                fontWeight: FontWeight.w900,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Effective: June 2026  ·  Last updated: June 2026',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textDim, fontSize: 12),
            ),
            const SizedBox(height: 24),

            // ── Top summary banner ──
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppTheme.accent.withOpacity(0.07),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.accent.withOpacity(0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lock_outline, color: AppTheme.accent, size: 24),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'The short version: Synchronization does not collect your audio, personal data, or browsing history. Audio streams travel directly between your devices peer-to-peer. Our server is never in the audio path. No ads targeting. No user accounts. No data sold.',
                      style: TextStyle(color: AppTheme.textDim, fontSize: 13, height: 1.6),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            _PolicySection(
              number: '1',
              title: 'What Synchronization Does',
              body: 'Synchronization is a local-network audio streaming tool with two modes:',
              bullets: const [
                'Browser Extension → Phone: The Chrome Extension captures audio from a browser tab and streams it to this App via WebRTC peer-to-peer over your local Wi-Fi or mobile hotspot.',
                'Phone → Phone: The App can host a local audio session where one phone streams a media file to other phones on the same network.',
              ],
              footer: 'In both modes, audio travels directly between your devices. It does not pass through our servers at any point.',
            ),

            _PolicySection(
              number: '2',
              title: 'Data We Collect',
              body: 'We collect no personal data whatsoever. Specifically:',
              bullets: const [
                'No name, email address, phone number, or account information is ever requested or stored.',
                'No audio data is recorded, intercepted, or transmitted to us.',
                'No browsing history or tab content is accessed beyond what is required to capture audio from the tab you explicitly activate.',
                'No device identifiers, advertising IDs, or analytics fingerprints are collected.',
                'No cookies or persistent trackers are placed on your device.',
              ],
            ),

            _PolicySection(
              number: '3',
              title: 'Audio Recording and Playback',
              body: 'The Synchronization Chrome Extension uses the browser\'s tabCapture API to access the audio output of the active tab — only when you click Start Streaming. This audio is:',
              bullets: const [
                'Streamed in real time directly to your paired phone via WebRTC.',
                'Never saved to disk, never uploaded to any server.',
                'Discarded immediately when you stop streaming or close the extension.',
              ],
              footer: 'The Android App receives and plays this stream. Audio is rendered locally on your phone and is not retained after playback ends.',
            ),

            _PolicySection(
              number: '4',
              title: 'Network Communication',
              body: 'To establish a connection, Synchronization uses a lightweight signaling server. Its only job is to exchange connection metadata (ICE candidates and SDP offers) between your two devices so they can find each other.',
              bullets: const [
                'The signaling server does NOT relay or record any audio.',
                'Connection metadata is ephemeral and discarded once the connection is established.',
                'The signaling server does not log IP addresses for retention purposes.',
                'Once peers are connected, all audio flows peer-to-peer and the signaling server is no longer involved.',
              ],
            ),

            _PolicySection(
              number: '5',
              title: 'Permissions Summary',
              body: 'Android App permissions requested:',
              bullets: const [
                'CAMERA — Used solely for scanning the QR code shown by the extension. No photos or video are taken or stored.',
                'INTERNET — Required for WebRTC and signaling server communication.',
                'WAKE_LOCK — Prevents the phone screen from sleeping while actively receiving an audio stream.',
                'ACCESS_FINE_LOCATION — Used for nearby-session discovery on your local network (Wi-Fi SSID scan). Your GPS location is never transmitted anywhere.',
                'READ_MEDIA_AUDIO — Required for phone-to-phone mode where you select a local audio file to host.',
              ],
            ),

            _PolicySection(
              number: '6',
              title: 'Third-Party Services',
              body: 'Synchronization uses the following third-party infrastructure:',
              bullets: const [
                'Cloud hosting (Render) — Used to host the signaling server and website. Standard server access logs may be maintained by the platform provider.',
                'WebRTC (open standard) — The audio transport layer. WebRTC uses STUN servers to discover network addresses during connection setup. These lookups are transient and do not persist.',
                'Google Mobile Ads — The app displays non-personalized banner and interstitial ads to sustain free distribution. Ad SDK behavior is governed by Google\'s own privacy policy.',
              ],
              footer: 'We do not integrate social media SDKs, analytics platforms, or data brokers beyond what is stated above.',
            ),

            _PolicySection(
              number: '7',
              title: 'Data Retention',
              body: 'We do not retain any user data. Session IDs are random identifiers generated fresh for each streaming session and are not associated with your identity.\n\nThe only persistent data is the signaling server URL stored locally on your device by the app or extension. You can clear this at any time through your device\'s app settings.',
            ),

            _PolicySection(
              number: '8',
              title: "Children's Privacy",
              body: 'Synchronization does not knowingly collect any information from children under the age of 13. We do not have age-gating mechanisms because we collect no personal information from any user of any age.',
            ),

            _PolicySection(
              number: '9',
              title: 'User Control',
              body: 'Because we collect no personal data, there is nothing to request, export, or delete. You are in full control:',
              bullets: const [
                'Uninstalling the Chrome Extension immediately removes all locally stored settings.',
                'Uninstalling the Android App immediately removes all locally stored settings.',
                'Stopping a streaming session immediately terminates all peer connections and frees all audio resources.',
              ],
            ),

            _PolicySection(
              number: '10',
              title: 'Changes to This Policy',
              body: 'We may update this Privacy Policy from time to time to reflect changes in the application\'s functionality. Any changes will be posted on our website with an updated effective date. Because we do not collect contact information, we cannot notify you directly.',
            ),

            _PolicySection(
              number: '11',
              title: 'Contact',
              body: 'If you have any questions about this Privacy Policy, contact us through the project\'s GitHub repository or the official Synchronization website.\n\nSynchronization Labs · June 2026',
            ),

            const SizedBox(height: 20),
            const Center(
              child: Text(
                '© 2026 Synchronization Labs',
                style: TextStyle(color: AppTheme.textDim, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Reusable policy section ─────────────────────────────────────────────────

class _PolicySection extends StatelessWidget {
  const _PolicySection({
    required this.number,
    required this.title,
    this.body,
    this.bullets,
    this.footer,
  });

  final String number;
  final String title;
  final String? body;
  final List<String>? bullets;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppTheme.accent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      number,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: AppTheme.accent,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(color: AppTheme.border, height: 1),
            const SizedBox(height: 12),
            if (body != null) ...[
              Text(body!, style: const TextStyle(color: AppTheme.textDim, fontSize: 13, height: 1.7)),
              if (bullets != null) const SizedBox(height: 10),
            ],
            if (bullets != null)
              ...bullets!.map((b) => _BulletItem(text: b)),
            if (footer != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.accent.withOpacity(0.2)),
                ),
                child: Text(
                  footer!,
                  style: const TextStyle(
                    color: AppTheme.textDim,
                    fontSize: 12,
                    height: 1.6,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BulletItem extends StatelessWidget {
  const _BulletItem({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('✓ ', style: TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w900, fontSize: 13)),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: AppTheme.textDim, fontSize: 13, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
