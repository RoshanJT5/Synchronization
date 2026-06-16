import 'package:flutter/material.dart';
import 'package:synchronization/theme/app_theme.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: const Text('About Us'),
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
            // ── Hero badge ──
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.accent.withOpacity(0.6)),
                ),
                child: const Text(
                  'ABOUT SYNCHRONIZATION',
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

            // ── Headline ──
            const Text(
              'Audio, Untethered.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 30,
                fontWeight: FontWeight.w900,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'The story of what we built, why, and how it works.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textDim, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 28),

            // ── What is it ──
            _InfoBlock(
              icon: Icons.graphic_eq,
              title: 'What is Synchronization?',
              body:
                  'Synchronization lets you stream any audio playing in your desktop browser directly to your Android phone wirelessly, with virtually zero perceptible delay.\n\n'
                  'One device acts as the source: your computer, running the Synchronization Chrome Extension. Other devices join instantly and hear the same audio in lock-step no cloud service, no internet relay, no accounts.',
            ),
            const SizedBox(height: 14),

            // ── Why built ──
            _InfoBlock(
              icon: Icons.help_outline,
              title: 'Why Was It Built?',
              body: 'Listening to audio from your laptop on another device is harder than it should be:',
              bullets: const [
                'Bluetooth is limited range, compression, and audio delay make it unsuitable for synchronized playback.',
                'Streaming services add their own delay two devices playing the same stream drift apart by seconds.',
                'Sharing headphones is not always practical, especially at a distance.',
                'Existing tools require manual IP configuration and firewall rules.',
              ],
              footer:
                  'Synchronization solves this with a fast, direct audio connection between your PC and your phone focused on precision synchronization and low latency.',
            ),
            const SizedBox(height: 14),

            // ── How it works ──
            _InfoBlock(
              icon: Icons.settings_input_antenna,
              title: 'How Does It Work?',
              bullets: const [
                'The Chrome Extension captures audio from your active browser tab using the browser\'s tabCapture API no screen recording, no microphone, just tab audio.',
                'A unique session QR code is generated instantly. Scan it from this app to pair your devices in seconds.',
                'Audio streams peer-to-peer via WebRTC directly from your computer to your phone over your local Wi-Fi or hotspot.',
                'Playback stays aligned across all connected devices using clock-calibrated scheduling and drift correction algorithms.',
                'Our signaling server is only used for the initial handshake. It never touches your audio.',
              ],
              footer:
                  'No accounts. No cloud audio. No firewall configuration required.',
            ),
            const SizedBox(height: 14),

            // ── Extension callout ──
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.accent.withOpacity(0.12),
                    AppTheme.accentDark.withOpacity(0.06),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.accent.withOpacity(0.45)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.extension, color: AppTheme.accent, size: 22),
                      const SizedBox(width: 10),
                      const Text(
                        'Connect the Chrome Extension',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Synchronization requires the Chrome Extension to be installed on your desktop browser. The extension captures your tab audio and generates the QR code this app scans to connect.',
                    style: TextStyle(color: AppTheme.textDim, fontSize: 13, height: 1.6),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'How to install the Extension:',
                          style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 12),
                        ),
                        SizedBox(height: 8),
                        _StepText(step: '1', text: 'Download the Extension ZIP from our website.'),
                        _StepText(step: '2', text: 'Extract the ZIP file.'),
                        _StepText(step: '3', text: 'Open Chrome → chrome://extensions'),
                        _StepText(step: '4', text: 'Enable Developer Mode (top right).'),
                        _StepText(step: '5', text: 'Click "Load unpacked" → select the extracted folder.'),
                        _StepText(step: '6', text: 'Click Start Streaming, then scan the QR code here.'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // ── When useful ──
            _InfoBlock(
              icon: Icons.check_circle_outline,
              title: 'When Is It Useful?',
              bullets: const [
                'Watching a video on your laptop while your Bluetooth headphones are already paired to your phone.',
                'Moving around the house while a movie or podcast plays on your desktop browser.',
                'Your laptop\'s headphone jack is broken or occupied.',
                'Creating a multi-room audio setup where multiple phones play the same audio in sync.',
                'Any situation where timing and audio fidelity matter.',
              ],
              footer: 'If everyone needs to hear the same thing at the same moment, Synchronization is built for that.',
            ),
            const SizedBox(height: 14),

            // ── Phone to Phone ──
            _InfoBlock(
              icon: Icons.smartphone,
              title: 'Phone-to-Phone Mode',
              body:
                  'The Synchronization App also supports phone-to-phone sharing. One phone acts as the host it selects a local media file, starts an internal audio stream, and announces the session. Guest phones scan the QR code and play the same audio in lock-step sync via precision clock calibration.\n\n'
                  'Both devices must be on the same Wi-Fi network, or the host phone can create a mobile hotspot for guests to join.',
            ),
            const SizedBox(height: 14),

            // ── Our focus ──
            _InfoBlock(
              icon: Icons.shield_outlined,
              title: 'Our Focus',
              body:
                  'Synchronization is built with a focus on performance, privacy, and simplicity. We do not run ads beyond what sustains the free app, we do not collect personal data, and we do not require you to create an account.\n\n'
                  'The core technology WebRTC peer-to-peer audio, precision clock-based sync scheduling, and drift correction is designed to keep audio aligned within tens of milliseconds across all connected devices, even on real-world consumer networks.',
            ),
            const SizedBox(height: 28),

            // ── Footer ──
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

// ── Reusable section block ──────────────────────────────────────────────────

class _InfoBlock extends StatelessWidget {
  const _InfoBlock({
    required this.icon,
    required this.title,
    this.body,
    this.bullets,
    this.footer,
  });

  final IconData icon;
  final String title;
  final String? body;
  final List<String>? bullets;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppTheme.accent, size: 20),
              const SizedBox(width: 10),
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
          if (body != null) ...[
            Text(body!, style: const TextStyle(color: AppTheme.textDim, fontSize: 13, height: 1.7)),
            const SizedBox(height: 8),
          ],
          if (bullets != null)
            ...bullets!.map((b) => _BulletRow(text: b)),
          if (footer != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.accent.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.accent.withOpacity(0.25)),
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
    );
  }
}

class _BulletRow extends StatelessWidget {
  const _BulletRow({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('→ ', style: TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w700, fontSize: 13)),
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

class _StepText extends StatelessWidget {
  const _StepText({required this.step, required this.text});
  final String step;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            margin: const EdgeInsets.only(right: 8, top: 1),
            decoration: const BoxDecoration(
              color: AppTheme.accent,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                step,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: AppTheme.textDim, fontSize: 12, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
