import 'package:flutter/material.dart';
import 'package:synchronization/theme/app_theme.dart';

class TermsAndConditionsScreen extends StatelessWidget {
  const TermsAndConditionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: const Text('Terms & Conditions'),
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
                  'TERMS & CONDITIONS',
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
              'Terms of Use.',
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

            // ── Top notice ──
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppTheme.accent.withOpacity(0.07),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.accent.withOpacity(0.3)),
              ),
              child: const Text(
                'Please read these Terms carefully before using Synchronization. By downloading, installing, or using the Synchronization Chrome Extension or Android Application, you agree to be bound by these Terms and Conditions.',
                style: TextStyle(color: AppTheme.textDim, fontSize: 13, height: 1.6),
              ),
            ),
            const SizedBox(height: 20),

            _TermsSection(
              number: '1',
              title: 'Acceptance of Terms',
              body:
                  'These Terms and Conditions ("Terms") govern your access to and use of the Synchronization software, which includes the Synchronization Chrome Extension ("Extension"), the Synchronization Android Application ("App"), and the associated website and signaling infrastructure (collectively, "Synchronization").\n\n'
                  'These Terms apply to all users. By using any part of the Service, you represent that you are at least 13 years of age and that you agree to these Terms.',
            ),

            _TermsSection(
              number: '2',
              title: 'Description of the Service',
              body: 'Synchronization is a peer-to-peer wireless audio streaming tool with two primary functions:',
              bullets: const [
                'Browser-to-Phone streaming: The Chrome Extension captures audio from a browser tab and streams it in real time to the Android App via WebRTC over a local Wi-Fi or hotspot connection.',
                'Phone-to-Phone streaming: The Android App can host a local audio session from a file stored on the device, allowing other devices on the same network to receive and play the audio in synchronized playback.',
              ],
              footer:
                  'Synchronization does not provide or distribute any media content. It is solely a transport layer for audio that you already have access to through your own licensed services or local files.',
            ),

            // Extension callout within terms
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.accent.withOpacity(0.10),
                    AppTheme.accentDark.withOpacity(0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppTheme.accent.withOpacity(0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Row(
                    children: [
                      Icon(Icons.extension, color: AppTheme.accent, size: 20),
                      SizedBox(width: 10),
                      Text(
                        'Using the Chrome Extension',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  Text(
                    'The Synchronization Chrome Extension is required to use the browser-to-phone audio streaming feature. It is installed manually from the ZIP file provided on our website.\n\n'
                    'To install: download the Extension ZIP, extract it, navigate to chrome://extensions in Chrome, enable Developer mode, and click "Load unpacked" to select the extracted folder.\n\n'
                    'By installing and using the Extension, you acknowledge that it requests access to the audio output of browser tabs you actively choose to stream, and that no audio is captured without your explicit action.',
                    style: TextStyle(color: AppTheme.textDim, fontSize: 13, height: 1.65),
                  ),
                ],
              ),
            ),

            _TermsSection(
              number: '3',
              title: 'Acceptable Use',
              body: 'You agree to use Synchronization only for lawful purposes. You must not use the Service to:',
              bullets: const [
                'Stream, distribute, or reproduce copyrighted audio content in ways that violate the terms of the content owner or applicable copyright law.',
                'Circumvent digital rights management (DRM) protections on content.',
                'Intercept, monitor, or capture audio content from third-party services in violation of their Terms of Service.',
                'Use the Service for any unlawful purpose or in violation of any local, national, or international regulation.',
                'Attempt to reverse-engineer, modify, or disrupt the signaling server infrastructure for other users.',
              ],
              footer:
                  'You are solely responsible for ensuring that your use of Synchronization complies with all content licenses and legal requirements applicable to the audio content you choose to stream.',
            ),

            _TermsSection(
              number: '4',
              title: 'Intellectual Property',
              body:
                  'All software, branding, design, and documentation associated with Synchronization are owned by Synchronization Labs and protected by applicable intellectual property laws. You are granted a limited, non-exclusive, non-transferable, revocable license to use the software for personal, non-commercial purposes in accordance with these Terms.\n\n'
                  'You may not copy, modify, sublicense, sell, or distribute the Synchronization software or any portion thereof without prior written permission from Synchronization Labs.',
            ),

            _TermsSection(
              number: '5',
              title: 'Disclaimer of Warranties',
              body: 'Synchronization is provided "as is" and "as available" without warranties of any kind, either express or implied. To the fullest extent permitted by law, Synchronization Labs expressly disclaims all warranties, including but not limited to:',
              bullets: const [
                'Implied warranties of merchantability, fitness for a particular purpose, and non-infringement.',
                'Warranties that the Service will be uninterrupted, error-free, or free of viruses or other harmful components.',
                'Warranties regarding the accuracy, reliability, or completeness of any audio transmitted through the Service.',
              ],
              footer:
                  'Audio synchronization quality depends on local network conditions, device hardware, and operating system behavior. We do not guarantee a specific maximum latency on any particular device or network.',
            ),

            _TermsSection(
              number: '6',
              title: 'Limitation of Liability',
              body:
                  'To the maximum extent permitted by applicable law, Synchronization Labs shall not be liable for any indirect, incidental, special, consequential, or punitive damages arising out of or in connection with your use of, or inability to use, the Service.\n\n'
                  'This includes, without limitation, damages for loss of profits, data, goodwill, or other intangible losses, even if Synchronization Labs has been advised of the possibility of such damages.',
            ),

            _TermsSection(
              number: '7',
              title: 'Your Content Responsibility',
              body: 'Synchronization is a transport tool. We do not control, curate, moderate, or have visibility into what audio content you choose to stream. You are entirely responsible for:',
              bullets: const [
                'Ensuring you have the legal right to stream any audio content you transmit through the Service.',
                'Complying with the terms of service of the platform providing the content you are streaming.',
                'Ensuring that the recipients of your audio stream have appropriate access to the content.',
              ],
            ),

            _TermsSection(
              number: '8',
              title: 'Network and Device Requirements',
              body: 'Synchronization relies on local network connectivity between your devices. For best results:',
              bullets: const [
                'All devices should be on the same Wi-Fi network, or the phone should create a mobile hotspot for the computer to connect to.',
                'VPN software active on either device may prevent peer-to-peer connections from being established.',
                'Network-level device isolation (common on public or corporate Wi-Fi) will block device-to-device communication.',
                'Heavy network usage on the same network may affect audio quality.',
              ],
              footer:
                  'We recommend connecting to a 5 GHz Wi-Fi band and disabling Battery Saver on receiving devices for the smoothest playback experience.',
            ),

            _TermsSection(
              number: '9',
              title: 'Third-Party Services',
              body:
                  'Synchronization uses third-party infrastructure for hosting and WebRTC signaling. These third-party services are subject to their own terms and privacy policies, which we do not control.\n\n'
                  'Synchronization is not affiliated with, endorsed by, or in partnership with Google Chrome, YouTube, Spotify, Netflix, or any other content platform. These names are referenced solely for descriptive purposes.',
            ),

            _TermsSection(
              number: '10',
              title: 'Termination',
              body:
                  'You may stop using Synchronization at any time by uninstalling the Extension and/or App. Because no user accounts exist, there is no account to deactivate.\n\n'
                  'Synchronization Labs reserves the right to discontinue the signaling server or any part of the Service at any time, with or without notice.',
            ),

            _TermsSection(
              number: '11',
              title: 'Changes to These Terms',
              body:
                  'We reserve the right to modify these Terms at any time. Revised Terms will be posted on our website with an updated effective date. Your continued use of the Service after such changes constitutes your acceptance of the new Terms.',
            ),

            _TermsSection(
              number: '12',
              title: 'Governing Law',
              body:
                  'These Terms shall be governed by and construed in accordance with applicable laws, without regard to conflict of law principles. Any disputes arising from these Terms or your use of Synchronization shall be subject to the jurisdiction of the competent courts applicable to Synchronization Labs.',
            ),

            _TermsSection(
              number: '13',
              title: 'Contact',
              body:
                  'If you have questions about these Terms, please contact us through the project\'s official GitHub repository or website.\n\nSynchronization Labs · June 2026',
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

// ── Reusable terms section ──────────────────────────────────────────────────

class _TermsSection extends StatelessWidget {
  const _TermsSection({
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
