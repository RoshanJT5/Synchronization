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
              'Effective: June 1, 2026  ·  Last updated: July 2026',
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
                      'Plain-language summary: Synchronization does not record, store, or upload your audio. Your GPS coordinates are used only to find nearby sessions and are deleted from our server the moment a session ends. The only third party that collects data about you is Google AdMob, which serves advertisements inside the app. We do not sell your data to anyone.',
                      style: TextStyle(color: AppTheme.textDim, fontSize: 13, height: 1.6),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            _PolicySection(
              number: '1',
              title: 'Who We Are and Scope of This Policy',
              body: 'This Privacy Policy is published by Roshan Talreja, operating under the trade name Synchronization Labs ("we," "us," or "our"), an individual independent developer based in Ahmedabad, Gujarat, India.\n\n'
                    'This Policy governs the collection, use, storage, and disclosure of information in connection with the Synchronization Android application, the Synchronization Chrome Extension, and the associated website hosted at synchronizationpro.app (collectively, the "Service").\n\n'
                    'This Policy applies to all users of the Service worldwide, including users in the United States, Canada, the European Economic Area, the United Kingdom, Australia, India, and all other jurisdictions. By installing or using the Service, you acknowledge that you have read and understood this Policy. If you do not agree, you must discontinue use of the Service immediately.\n\n'
                    'Acceptance by use. By downloading, installing, or accessing any part of the Service, you represent that you have read this Privacy Policy and the Terms and Conditions in their entirety and that you agree to be bound by both documents. If you do not agree with any part of this Policy, you must not use the Service. We may update this Policy at any time without prior notice. Your continued use of the Service after any update constitutes your acceptance of the revised Policy.',
            ),

            _PolicySection(
              number: '2',
              title: 'Information We Collect and Why',
              body: 'Synchronization is built to collect the minimum information necessary to operate the Service. Below is a complete and transparent account of every category of data that is collected, how it is used, and how long it is retained.\n\n'
                    '2.1 GPS Location Coordinates\n'
                    'When you host or join a Phone-to-Phone session, the app requests your precise GPS coordinates (latitude and longitude) using the Android ACCESS_FINE_LOCATION and ACCESS_COARSE_LOCATION permissions. These coordinates are transmitted to our signaling server hosted on Virtual Machine solely to power the Nearby Session Discovery feature, which displays only sessions within a 50-meter radius of your current position.\n\n'
                    'Your GPS coordinates are stored exclusively in volatile RAM on the signaling server for the duration of your active session. They are automatically and permanently deleted from the server the moment you end your session, the session times out, or you close the application. We do not build location history profiles. We do not log your coordinates to any persistent database. We do not use your location data for advertising targeting, analytics, or any purpose other than the proximity filter described above.\n\n'
                    '2.2 WebRTC Session Metadata\n'
                    'To establish a peer-to-peer connection between your devices, our signaling server temporarily processes a randomly generated session ID and standard WebRTC handshake data (SDP offer/answer messages and ICE candidates). This metadata is ephemeral and is discarded from the server as soon as the direct connection between your devices is established. It is never logged to disk or retained in any database.\n\n'
                    '2.3 Audio and Media Content\n'
                    'We do not collect, record, intercept, or store any audio content transmitted through the Service. All audio streams are processed transiently in device memory and travel peer-to-peer directly between your devices. Audio never passes through or touches our signaling server. When you select a local media file for Phone-to-Phone hosting, that file is read locally on your device and streamed directly to guest devices over your local network. It is never uploaded to our servers or any external cloud storage.\n\n'
                    '2.4 Data We Do Not Collect',
              bullets: const [
                'No name, email address, phone number, or account credentials. The Service has no user accounts.',
                'No browsing history, tab URLs, or tab content beyond what is strictly necessary to capture audio from a tab you explicitly activate for streaming.',
                'No device identifiers, advertising IDs, or hardware fingerprints collected by us directly. Note that Google AdMob, described in Section 5, does collect advertising identifiers independently.',
                'No analytics, behavioral telemetry, crash reports, or usage statistics transmitted to our servers.',
                'No payment information. The Service is entirely free.',
                'No photographs, video recordings, or images captured through the camera permission. The camera is used solely for QR code scanning.',
              ],
            ),

            _PolicySection(
              number: '3',
              title: 'How Audio Streaming Works',
              body: 'The Service operates in two modes. Understanding these modes is important for evaluating your privacy.\n\n'
                    'Browser-to-Phone mode. The Chrome Extension uses the browser\'s native tabCapture API to capture the audio output of a single browser tab that you explicitly designate. This audio is transmitted in real time via an encrypted WebRTC peer-to-peer connection directly to your Android device over your local Wi-Fi network or mobile hotspot. The audio does not pass through our signaling server at any point. Synchronization Labs has no technical ability to access or intercept this audio stream.\n\n'
                    'Phone-to-Phone mode. One phone acts as a host, reading a media file stored locally on that device. The audio is streamed directly to guest phones over your local network using encrypted WebRTC peer-to-peer connections and data channels. Playback synchronization commands are transmitted over an encrypted WebRTC data channel between devices. The media file is never uploaded to any external server. Synchronization Labs has no access to any media content transmitted in this mode.\n\n'
                    'WebRTC TURN relay servers. In circumstances where a direct peer-to-peer connection cannot be established due to network configuration or firewall restrictions, audio traffic may be routed through encrypted third-party TURN relay servers. These relay servers handle only encrypted data packets and cannot access or store the audio content contained within. We use TURN relay infrastructure provided by third-party providers including Metered.ca and ExpressTURN. These providers process data pursuant to their own privacy policies.',
            ),

            _PolicySection(
              number: '4',
              title: 'Device Permissions Requested',
              body: 'The following permissions are requested by the Android application. Each permission is used only for the specific stated purpose.',
              bullets: const [
                'ACCESS_FINE_LOCATION, ACCESS_COARSE_LOCATION — Required to determine your GPS coordinates for the 50-meter Nearby Session Discovery filter. Used only when you host or join a session. Not used for advertising targeting by us.',
                'CAMERA — Used exclusively to scan QR codes displayed by the Chrome Extension or other host devices. No photographs or video recordings are taken, stored, or transmitted.',
                'INTERNET, ACCESS_NETWORK_STATE, ACCESS_WIFI_STATE — Required for WebRTC peer-to-peer connections and communication with the signaling server.',
                'READ_MEDIA_AUDIO, READ_MEDIA_VIDEO, READ_EXTERNAL_STORAGE — Required in Phone-to-Phone host mode to allow you to select a local audio or video file from your device storage to broadcast to guest devices. Files are read locally and are never uploaded.',
                'MODIFY_AUDIO_SETTINGS — Required to configure audio routing and output during active streaming sessions.',
                'FOREGROUND_SERVICE, FOREGROUND_SERVICE_MEDIA_PLAYBACK, WAKE_LOCK — Required to keep the audio session active when the app is in the background or the screen is locked, functioning similarly to a music streaming application.',
                'REQUEST_IGNORE_BATTERY_OPTIMIZATIONS — Requested to prevent Android from suspending the foreground audio service during extended sessions.',
                'BLUETOOTH, BLUETOOTH_CONNECT — Required to route audio output to connected Bluetooth headphones or speakers correctly.',
              ],
              footer: 'Chrome Extension permissions (Manifest V3):\n\n'
                      '• tabCapture — Captures audio from the browser tab you select. Active only when you explicitly start a streaming session.\n'
                      '• activeTab — Identifies the current browser tab for capture. No tab content, URLs, or history are accessed or stored.\n'
                      '• storage — Stores your saved signaling server URL locally in the browser. This preference data never leaves your device.\n'
                      '• offscreen — Required by Chrome Manifest V3 to run audio processing in a background context.',
            ),

            _PolicySection(
              number: '5',
              title: 'Google AdMob and Third-Party Advertising',
              body: 'The Service displays advertisements served by Google AdMob, a product of Google LLC. This is the sole method of monetization for the Service. AdMob operates independently and collects certain data from users for the purpose of delivering and measuring advertisements. This section discloses exactly what AdMob does, as required by applicable law.\n\n'
                    'What Google AdMob collects. When you use the Service, Google AdMob may automatically collect the following categories of data directly from your device, independently of anything Synchronization Labs does:',
              bullets: const [
                'Android Advertising ID (GAID) or equivalent device advertising identifier.',
                'IP address, which may be used to derive approximate geographic location.',
                'Device information including manufacturer, model, operating system version, and screen resolution.',
                'App usage data including which ads are displayed, viewed, or interacted with.',
                'Diagnostic and performance data related to ad delivery.',
              ],
              footer: 'Personalized advertising disclosure. The Service currently uses AdMob\'s default settings, which means Google may serve personalized advertisements based on your interests and prior online activity. Synchronization Labs does not control or direct the personalization logic. Google\'s own data collection and processing practices for advertising are governed by the Google Privacy Policy, available at policies.google.com/privacy.\n\n'
                      'Your opt-out rights. You may opt out of personalized advertising at any time by visiting your Android device Settings, navigating to Google, then Ads, and selecting "Delete advertising ID" or "Opt out of Ads Personalization." On devices running Android 12 and above, you can delete your Advertising ID entirely. These controls are provided by Google and are independent of Synchronization Labs.\n\n'
                      'GDPR notice for EEA and UK users. If you are located in the European Economic Area or the United Kingdom, the General Data Protection Regulation and UK GDPR require prior explicit consent before personalized advertisements or advertising identifiers are collected. The Service does not currently implement a Consent Management Platform (CMP). Until a compliant CMP is integrated in a future update, personalized advertisements may be served to all users including those in the EEA and UK. If you are in the EEA or UK and do not consent to personalized advertising, you should use the device-level opt-out described above and consider not using the Service until the consent mechanism is implemented. We acknowledge this as a known compliance limitation and are working to resolve it.\n\n'
                      'CCPA notice for California residents. Under the California Consumer Privacy Act, sharing data with advertising networks may constitute a "sale" or "sharing" of personal information. By using the Service, Google AdMob may receive personal information about you as described above. You have the right to opt out of the sharing of your personal information for cross-context behavioral advertising purposes by using the device-level opt-out controls described in this section.',
            ),

            _PolicySection(
              number: '6',
              title: 'Third-Party Services and Infrastructure',
              bullets: const [
                'Google Cloud (signaling server hosting). Our signaling server is hosted on a Google Cloud Compute Engine e2-micro virtual machine. Google Cloud may process connection metadata including IP addresses pursuant to the Google Cloud Privacy Policy at cloud.google.com/terms/cloud-privacy-notice. We do not add application-level logging of user requests beyond what the signaling function requires.',
                'Cloudflare (website hosting). Our website at synchronizationpro.app is hosted on Cloudflare Workers. Cloudflare may process connection metadata pursuant to their privacy policy at cloudflare.com/privacypolicy.',
                'WebRTC STUN servers. WebRTC uses public STUN servers, including those operated by Google, during ICE negotiation to facilitate NAT traversal. These servers receive your device\'s public IP address momentarily. This interaction is standard to the WebRTC protocol and is governed by the STUN server operator\'s own policies.',
                'TURN relay servers. If a direct connection cannot be established, encrypted audio packets may be routed through third-party TURN relay infrastructure. These servers route encrypted data only and cannot access the content of your audio stream.',
                'Google AdMob. Described in full in Section 5 above.',
              ],
              footer: 'We do not integrate any social media SDKs, analytics platforms, crash reporting tools, or data broker services. We do not sell your personal information to any third party.',
            ),

            _PolicySection(
              number: '7',
              title: "Children's Privacy",
              body: 'The Service is not directed to children under the age of 13. In accordance with the Children\'s Online Privacy Protection Act (COPPA) of the United States and applicable international children\'s privacy laws, we do not knowingly collect personal information from children under 13 years of age.\n\n'
                    'Because the Service incorporates Google AdMob, which may collect advertising identifiers, the minimum age for use of this Service is 13 years old. The app is rated accordingly on the Google Play Store.\n\n'
                    'If you are a parent or guardian and believe your child under the age of 13 has used the Service, please contact us at roshantalreja05@outlook.com and we will take immediate steps to address the concern. If AdMob has collected data attributable to a child under 13, we will contact Google to request deletion in accordance with COPPA requirements.',
            ),

            _PolicySection(
              number: '8',
              title: 'Your Privacy Rights by Jurisdiction',
              body: 'Depending on where you are located, you may have specific legal rights regarding your personal information. Because Synchronization Labs collects very limited personal data directly, most rights requests will relate primarily to data held by Google AdMob. In all cases, we will do our best to assist you.',
              bullets: const [
                'California (CCPA/CPRA). You have the right to know what personal information is collected, the right to delete personal information, and the right to opt out of the sale or sharing of personal information. We do not sell personal information. For AdMob-related data, use the device-level opt-out described in Section 5 and visit Google\'s Ad Settings at adssettings.google.com.',
                'European Economic Area and United Kingdom (GDPR / UK GDPR). You have the right to access, rectify, erase, and port your personal data, and the right to object to or restrict certain processing. For location data we hold transiently on our signaling server, you may contact us to request confirmation of deletion. For AdMob data, submit a request to Google at support.google.com/policies/troubleshooter/7575787. You also have the right to lodge a complaint with your local data protection supervisory authority.',
                'Canada (PIPEDA / Law 25). You have the right to access personal information held about you and to request correction of inaccuracies. Because we retain GPS data only in volatile RAM for the duration of a session, no persistent personal information is held by us after a session ends. You may contact us with any privacy concern at roshantalreja05@outlook.com.',
                'India (DPDP Act 2023). You have the right to access information about personal data processed, the right to correction and erasure, and the right to grievance redressal. You may contact our grievance officer at roshantalreja05@outlook.com for any data-related concern.',
              ],
            ),

            _PolicySection(
              number: '9',
              title: 'Data Security',
              body: 'All audio and data transmitted through the Service is carried over WebRTC, which encrypts all media and data channels by default using DTLS-SRTP (Datagram Transport Layer Security with Secure Real-time Transport Protocol). This means your audio stream is encrypted in transit between your devices even on a shared local network.\n\n'
                    'GPS coordinates transmitted to our signaling server are sent over HTTPS and stored only in server RAM. They are never written to disk or a persistent database and are deleted automatically when a session ends.\n\n'
                    'Because we do not maintain a persistent database of user data, there is no central repository of personal information that could be exposed in a data breach. No method of electronic transmission is one hundred percent secure. However, the architecture of Synchronization is specifically designed to minimize the collection and retention of any personal information.',
            ),

            _PolicySection(
              number: '10',
              title: 'Data Retention',
              body: 'Synchronization Labs retains personal data for the shortest time possible consistent with operation of the Service.',
              bullets: const [
                'GPS coordinates are retained in volatile server RAM only for the duration of an active session and are permanently deleted when the session ends or times out.',
                'WebRTC session identifiers and handshake metadata are discarded from the signaling server immediately upon successful peer-to-peer connection establishment.',
                'No audio content or media files are retained on our servers at any time.',
                'The only persistent data is local application preferences stored on your own device, such as a saved signaling server URL, which is deleted when you uninstall the application.',
              ],
            ),

            _PolicySection(
              number: '11',
              title: 'Changes to This Privacy Policy',
              body: 'We reserve the right to update or modify this Privacy Policy at any time and without prior notice. All changes will be effective immediately upon posting to this page with a revised effective date. Because we do not collect contact information, we cannot notify you directly of changes. Your continued use of the Service after any modification constitutes your acceptance of the updated Policy. We encourage you to review this page periodically, particularly when new features are added to the Service.',
            ),

            _PolicySection(
              number: '12',
              title: 'Contact Us',
              body: 'If you have any questions, concerns, or requests relating to this Privacy Policy or the privacy practices of Synchronization Labs, please contact us directly.\n\n'
                    'Email: roshantalreja05@outlook.com\n\n'
                    'Roshan Talreja, operating as Synchronization Labs · Ahmedabad, Gujarat, India · Effective June 1, 2026',
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
