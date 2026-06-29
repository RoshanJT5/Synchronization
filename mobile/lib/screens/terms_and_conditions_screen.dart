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
                'Please read these Terms carefully before using Synchronization. These Terms of Use constitute a legally binding agreement between you and Roshan Talreja, operating as Synchronization Labs. By downloading, installing, accessing, or using any part of the Service, you confirm that you are at least 13 years of age, that you have read and understood these Terms in full, and that you agree to be bound by them. If you do not agree, you must not use the Service. We may update these Terms at any time without prior notice. Your continued use of the Service after any update constitutes your acceptance of the revised Terms.',
                style: TextStyle(color: AppTheme.textDim, fontSize: 13, height: 1.6),
              ),
            ),
            const SizedBox(height: 20),

            _TermsSection(
              number: '1',
              title: 'Definitions',
              bullets: const [
                '"Agreement" means these Terms of Use together with the Privacy Policy, which is incorporated herein by reference and forms part of this Agreement.',
                '"Synchronization Labs," "we," "us," or "our" means Roshan Talreja, an individual developer operating under the trade name Synchronization Labs, based in Ahmedabad, Gujarat, India.',
                '"Service" means the Synchronization Android application, the Synchronization Chrome Extension, the signaling server infrastructure, and the associated website at synchronization.labs5.workers.dev, collectively.',
                '"User," "you," or "your" means any individual who installs, accesses, or uses the Service in any capacity.',
                '"Content" means any audio, media files, or data that you choose to stream, transmit, or broadcast through the Service.',
                '"Session" means an active streaming connection established between two or more devices using the Service.',
              ],
            ),

            _TermsSection(
              number: '2',
              title: 'Description of the Service',
              body: 'Synchronization is a peer-to-peer audio streaming utility that enables you to transmit real-time audio from a desktop browser or a host mobile device to one or more Android devices connected to the same local Wi-Fi network or mobile hotspot. The Service functions as a transport layer only.\n\n'
                    'Synchronization Labs does not provide, host, distribute, license, curate, or control any media content transmitted through the Service. We are not a streaming service, a content platform, or a media library. We provide the technical infrastructure for devices you own or control to communicate with each other directly. You are entirely and solely responsible for all Content you choose to transmit through the Service.\n\n'
                    'The Service is provided free of charge and is supported by third-party advertisements served by Google AdMob. By using the Service, you acknowledge and accept that advertisements will be displayed within the application.',
            ),

            _TermsSection(
              number: '3',
              title: 'Acceptance by Use and Policy Updates',
              body: 'By downloading, installing, or using the Service in any manner, you represent and warrant that you have read this Agreement in its entirety, that you understand it, and that you agree to be bound by all of its terms and conditions. If you are using the Service on behalf of another person, you represent that you have the authority to bind that person to this Agreement.\n\n'
                    'We reserve the right to modify these Terms and the Privacy Policy at any time at our sole discretion, with or without notice to you. All modifications will be effective immediately upon being posted to our website with a revised effective date. Because we do not collect contact information, we are unable to provide direct notification of changes. Your continued access to or use of the Service after any modification constitutes your unconditional acceptance of the revised Terms. If you do not agree to the modified Terms, your sole remedy is to immediately discontinue use of the Service and uninstall all components.',
            ),

            _TermsSection(
              number: '4',
              title: 'Eligibility and Age Restriction',
              body: 'You must be at least 13 years of age to use the Service. This minimum age is set because the Service incorporates Google AdMob, which may collect advertising identifiers from users, and compliance with the Children\'s Online Privacy Protection Act (COPPA) of the United States and equivalent international children\'s privacy laws requires that such data collection not occur in connection with users under the age of 13.\n\n'
                    'If you are between 13 and 18 years of age, or between 13 and the applicable age of majority in your jurisdiction, you may use the Service only with the involvement and consent of a parent or legal guardian who agrees to be bound by this Agreement on your behalf.\n\n'
                    'By using the Service, you represent and warrant that you meet the eligibility requirements above. If we discover that a user is under 13 years of age, we will take reasonable steps to prevent that user from accessing the Service.',
            ),

            _TermsSection(
              number: '5',
              title: 'License Grant and Restrictions',
              body: 'Subject to your compliance with this Agreement, Synchronization Labs grants you a limited, personal, non-exclusive, non-transferable, revocable, royalty-free license to download, install, and use the Service solely for your personal, non-commercial purposes.\n\n'
                    'This license does not permit you to, and you expressly agree that you will not:',
              bullets: const [
                'Copy, modify, adapt, translate, reverse-engineer, decompile, disassemble, or create derivative works based on the Service or any part of it.',
                'Sublicense, sell, resell, rent, lease, transfer, or assign the Service or any rights therein to any third party.',
                'Remove, alter, or obscure any proprietary notices, copyright statements, or branding incorporated in the Service.',
                'Use the Service or any part of it to build a competing product or service, or extract features for use in a third-party application without prior written permission from Synchronization Labs.',
                'Attempt to circumvent any technical protection measures or security features of the Service.',
                'Use automated scripts, bots, or other automated means to access or interact with the Service.',
              ],
              footer: 'All rights not expressly granted to you in this Agreement are reserved by Synchronization Labs. The Service is licensed to you, not sold.',
            ),

            _TermsSection(
              number: '6',
              title: 'Acceptable Use and Prohibited Conduct',
              body: 'You agree to use the Service only in compliance with all applicable laws and regulations, including the laws of the United States, Canada, the European Union, India, and any other jurisdiction in which you access or use the Service. Without limiting the foregoing, you must not use the Service to:',
              bullets: const [
                'Stream, reproduce, retransmit, or publicly perform any audio or media content in a manner that infringes the copyright or other intellectual property rights of any person or entity, including violations of the Digital Millennium Copyright Act (DMCA), the Copyright Act (Canada), the EU Copyright Directive, or the Indian Copyright Act, 1957.',
                'Circumvent or bypass digital rights management (DRM) protections, technological protection measures, or access controls implemented by any content owner or distribution platform.',
                'Capture or retransmit audio from a third-party service in violation of that service\'s terms of use or applicable law.',
                'Transmit Content that is defamatory, obscene, harassing, threatening, discriminatory, or otherwise unlawful in any applicable jurisdiction.',
                'Interfere with, damage, disrupt, or gain unauthorized access to the signaling server infrastructure, any connected systems or networks, or any other user\'s session.',
                'Use the Service to facilitate the unauthorized distribution of copyrighted content to individuals who do not hold a lawful right to access it.',
                'Use the Service for any commercial purpose without our prior written consent, including using it to provide audio streaming services to paying customers.',
              ],
            ),

            _TermsSection(
              number: '7',
              title: 'Your Content and Copyright Responsibility',
              body: 'You retain all ownership rights in the Content you transmit through the Service. By using the Service to transmit Content, you represent and warrant that:',
              bullets: const [
                'You own the Content you transmit, or you have obtained all necessary licenses, rights, consents, and permissions from the copyright owner to stream that Content in the manner you are using the Service.',
                'Your use of the Service to transmit the Content does not and will not infringe, misappropriate, or violate the intellectual property rights, privacy rights, or any other rights of any third party.',
                'You have complied with and will continue to comply with the terms of service of any third-party platform providing the Content, including without limitation YouTube, Spotify, Netflix, Apple Music, Amazon Prime Video, and any other service.',
              ],
              footer: 'Safe harbor and conduit status. Synchronization Labs operates as a passive technical conduit in the same manner as an internet service provider or a network router. We do not monitor, intercept, store, review, or control the Content transmitted through the Service. We do not initiate transmissions, select recipients beyond what is necessary to establish the peer-to-peer connection you request, or modify Content in transit. Accordingly, we assert that we qualify for safe harbor protections under Section 512 of the Digital Millennium Copyright Act, the equivalent provisions of Canadian copyright law, the EU Electronic Commerce Directive, and equivalent conduit liability exemptions in other applicable jurisdictions.\n\n'
                      'You are entirely and solely responsible for any Content you transmit and for any legal consequences arising from your use of the Service to transmit that Content. Synchronization Labs shall have no liability whatsoever for any claims, damages, or proceedings arising from Content transmitted by users.',
            ),

            _TermsSection(
              number: '8',
              title: 'Third-Party Advertising',
              body: 'The Service displays third-party advertisements served by Google AdMob. By using the Service, you acknowledge and agree that:',
              bullets: const [
                'Advertisements will be displayed within the application during normal use, including upon opening the app, during sessions, and at other points within the user experience.',
                'Google AdMob may collect device identifiers and other data for the purposes of serving and measuring advertisements, as described in our Privacy Policy.',
                'Synchronization Labs is not responsible for the content of any third-party advertisement displayed within the Service. Any complaint or concern regarding ad content should be directed to Google.',
                'Synchronization Labs does not endorse any product or service advertised within the Service.',
              ],
              footer: 'Google\'s advertising services are governed by the Google Advertising Policies available at support.google.com/admob/answer/6128543 and Google\'s Privacy Policy at policies.google.com/privacy. By using the Service, you acknowledge that you are also subject to Google\'s policies with respect to the advertising functionality.',
            ),

            _TermsSection(
              number: '9',
              title: 'Third-Party Platforms and Content Services',
              body: 'The Service is technically capable of capturing and transmitting audio from any browser tab. Synchronization Labs is not affiliated with, endorsed by, sponsored by, or in partnership with any content platform, including Google, YouTube, Spotify, Netflix, Apple, Amazon, or any other third-party service.\n\n'
                    'Your use of any third-party content platform in conjunction with the Service is governed solely by that platform\'s own terms of service, end-user license agreements, and applicable law. It is your sole responsibility to review and comply with those terms before using the Service in connection with any third-party platform. We make no representation that any particular use of the Service in connection with a third-party platform is permitted by that platform\'s terms.',
            ),

            _TermsSection(
              number: '10',
              title: 'Network, Device, and Performance Disclaimer',
              body: 'The performance of the Service, including audio latency, synchronization precision, connection stability, and audio quality, depends on factors entirely outside our control, including the speed and stability of your local Wi-Fi network, your router configuration, your device hardware, your Android operating system version, and background process management by your device.\n\n'
                    'You acknowledge and accept that:',
              bullets: const [
                'All devices must be connected to the same Wi-Fi network or the host must provide a mobile hotspot. Network-level device isolation, enforced on many public, corporate, and institutional networks, will prevent the Service from functioning.',
                'Active VPN software on any participating device may prevent peer-to-peer connections from being established.',
                'Audio synchronization is a best-effort service. We do not guarantee any specific level of latency, synchronization precision, or audio quality. The Service is not suitable for professional or mission-critical audio applications, live performance use, emergency communications, or any situation in which audio failure could result in harm.',
                'Android battery optimization settings may interrupt background audio playback. We recommend disabling battery optimization for the application to maintain session continuity during extended use.',
                'The signaling server infrastructure is provided on an as-available basis. We do not guarantee any specific uptime, availability, or continuity of the signaling server service.',
              ],
            ),

            _TermsSection(
              number: '11',
              title: 'Intellectual Property',
              body: 'The Service, including all software code, user interface design, architecture, branding, trademarks, logos, and documentation, is owned by or licensed to Synchronization Labs and is protected by applicable intellectual property laws including the copyright laws of India, the United States, and other applicable jurisdictions.\n\n'
                    'Nothing in this Agreement transfers to you any ownership interest in the Service or any of its components. You may not use the Synchronization name, logo, or any related marks without our prior written consent.\n\n'
                    'Any feedback, ideas, suggestions, or recommendations you voluntarily provide to us regarding the Service may be used by us freely and without any obligation, compensation, or restriction.',
            ),

            _TermsSection(
              number: '12',
              title: 'Disclaimer of Warranties',
              body: 'THE SERVICE IS PROVIDED "AS IS" AND "AS AVAILABLE," WITHOUT WARRANTY OF ANY KIND. TO THE FULLEST EXTENT PERMITTED BY APPLICABLE LAW, SYNCHRONIZATION LABS EXPRESSLY DISCLAIMS ALL WARRANTIES, WHETHER EXPRESS, IMPLIED, STATUTORY, OR OTHERWISE, INCLUDING BUT NOT LIMITED TO THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, TITLE, AND NON-INFRINGEMENT.\n\n'
                    'SYNCHRONIZATION LABS MAKES NO WARRANTY THAT THE SERVICE WILL MEET YOUR REQUIREMENTS, OPERATE WITHOUT INTERRUPTION, ACHIEVE ANY PARTICULAR LEVEL OF AUDIO SYNCHRONIZATION OR LATENCY, BE FREE FROM ERRORS OR DEFECTS, OR BE FREE FROM VIRUSES OR OTHER HARMFUL COMPONENTS.\n\n'
                    'THE SERVICE IS NOT DESIGNED OR INTENDED FOR USE IN PROFESSIONAL AUDIO PRODUCTION, LIVE PERFORMANCE, BROADCAST, EMERGENCY COMMUNICATIONS, MEDICAL MONITORING, OR ANY OTHER SITUATION IN WHICH PERFORMANCE FAILURES COULD RESULT IN INJURY, FINANCIAL LOSS, OR HARM OF ANY KIND. USE OF THE SERVICE IN SUCH CONTEXTS IS AT YOUR OWN RISK AND IS EXPRESSLY OUTSIDE THE INTENDED PURPOSE OF THE SERVICE.\n\n'
                    'Some jurisdictions do not permit the exclusion of certain implied warranties. To the extent applicable law does not allow the full exclusion of implied warranties, the above exclusion applies to the maximum extent permitted by law in your jurisdiction.',
            ),

            _TermsSection(
              number: '13',
              title: 'Limitation of Liability',
              body: 'TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, SYNCHRONIZATION LABS, ITS DEVELOPER, AFFILIATES, AGENTS, AND LICENSORS SHALL NOT BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, EXEMPLARY, OR PUNITIVE DAMAGES, OR DAMAGES FOR LOSS OF PROFITS, REVENUE, DATA, GOODWILL, BUSINESS OPPORTUNITIES, OR OTHER INTANGIBLE LOSSES, ARISING OUT OF OR IN CONNECTION WITH YOUR USE OF, OR INABILITY TO USE, THE SERVICE, EVEN IF WE HAVE BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGES.\n\n'
                    'THIS LIMITATION APPLIES TO ALL CLAIMS, WHETHER BASED ON WARRANTY, CONTRACT, TORT (INCLUDING NEGLIGENCE), STRICT LIABILITY, STATUTE, OR ANY OTHER LEGAL OR EQUITABLE THEORY.\n\n'
                    'IN NO EVENT SHALL OUR TOTAL CUMULATIVE LIABILITY TO YOU FOR ALL CLAIMS ARISING OUT OF OR RELATING TO THE SERVICE EXCEED THE GREATER OF (A) THE TOTAL AMOUNT YOU PAID US IN THE TWELVE MONTHS PRECEDING THE CLAIM, WHICH FOR A FREE SERVICE IS ZERO, OR (B) ONE HUNDRED INDIAN RUPEES (INR 100).\n\n'
                    'Some jurisdictions, including certain Canadian provinces and EU member states, do not permit the exclusion or limitation of liability for certain types of damages. In those jurisdictions, the above limitation applies to the fullest extent permitted by applicable law, and our liability is limited to the minimum amount required by law.',
            ),

            _TermsSection(
              number: '14',
              title: 'Indemnification',
              body: 'You agree to defend, indemnify, and hold harmless Synchronization Labs and its developer, officers, agents, and licensors from and against any and all claims, liabilities, damages, losses, costs, and expenses (including reasonable legal fees) arising out of or relating to:',
              bullets: const [
                'Your use of the Service in violation of this Agreement or any applicable law;',
                'Your Content, including any claim that your Content infringes the intellectual property or other rights of any third party;',
                'Your violation of any third-party right, including any copyright, trademark, privacy, or other proprietary right;',
                'Any dispute between you and any third party arising from your use of the Service.',
              ],
            ),

            _TermsSection(
              number: '15',
              title: 'Termination',
              body: 'This Agreement is effective from the date you first install or access the Service and remains in effect until terminated. You may terminate this Agreement at any time by uninstalling the Chrome Extension and the Android application from all your devices.\n\n'
                    'Synchronization Labs reserves the right to suspend or discontinue the signaling server or any aspect of the Service at any time, with or without notice, for any reason, including for maintenance, security, legal compliance, or commercial reasons. We have no obligation to maintain the signaling server or the Service indefinitely. Discontinuation of the signaling server will prevent new peer-to-peer connections from being established but will not affect existing direct connections until they naturally terminate.\n\n'
                    'Sections 7, 11, 12, 13, 14, 16, and 17 of this Agreement shall survive any termination or expiration.',
            ),

            _TermsSection(
              number: '16',
              title: 'Governing Law and Dispute Resolution',
              body: 'This Agreement shall be governed by and construed in accordance with the laws of India, without regard to its conflict of law principles. The courts of Ahmedabad, Gujarat, India shall have jurisdiction over any dispute arising from this Agreement, subject to the mandatory consumer protection provisions described below.\n\n'
                    'Before initiating any formal legal proceeding, you agree to contact us at 230101027158git@gmail.com and make a good-faith effort to resolve the dispute informally. Most concerns can be resolved quickly and amicably.\n\n'
                    'If you are a consumer resident in the European Union or United Kingdom, nothing in this Agreement limits your right to bring claims in the courts of your country of residence or your mandatory rights under applicable consumer protection law. If you are a consumer resident in Canada, you retain any non-waivable rights under applicable provincial consumer protection legislation.',
            ),

            _TermsSection(
              number: '17',
              title: 'General Provisions',
              bullets: const [
                '"Entire Agreement." This Agreement, together with the Privacy Policy, constitutes the entire agreement between you and Synchronization Labs with respect to the Service and supersedes all prior agreements, representations, and understandings relating to the same subject matter.',
                '"Severability." If any provision of this Agreement is found to be invalid, illegal, or unenforceable by a court of competent jurisdiction, that provision shall be modified to the minimum extent necessary to make it enforceable, and all remaining provisions shall continue in full force and effect.',
                '"Waiver." Our failure to enforce any right or provision of this Agreement at any time shall not constitute a waiver of that right or provision. Any waiver must be in writing and signed by an authorized representative of Synchronization Labs to be effective.',
                '"Assignment." You may not assign or transfer your rights or obligations under this Agreement without our prior written consent. We may freely assign this Agreement, including in connection with a transfer of the Service, a merger, or a sale of assets.',
                '"No Agency." Nothing in this Agreement creates any partnership, joint venture, agency, franchise, or employment relationship between you and Synchronization Labs.',
                '"Force Majeure." We shall not be liable for any failure or delay in performance resulting from causes beyond our reasonable control, including natural disasters, government actions, power outages, internet infrastructure failures, or third-party service disruptions.',
              ],
            ),

            _TermsSection(
              number: '18',
              title: 'Contact Us',
              body: 'If you have any questions, concerns, or requests regarding these Terms, please contact Synchronization Labs directly.\n\n'
                    'Email: 230101027158git@gmail.com\n\n'
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
