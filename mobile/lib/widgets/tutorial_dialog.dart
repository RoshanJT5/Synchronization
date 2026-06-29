import 'package:flutter/material.dart';
import 'package:synchronization/theme/app_theme.dart';

class TutorialDialog extends StatefulWidget {
  const TutorialDialog({super.key});

  @override
  State<TutorialDialog> createState() => _TutorialDialogState();
}

class _TutorialDialogState extends State<TutorialDialog> {
  final PageController _controller = PageController();
  int _index = 0;

  static const List<_TutorialStep> _steps = [
    _TutorialStep(
      icon: Icons.graphic_eq,
      title: 'Welcome to Synchronization',
      subtitle: 'Listen together without fighting delay.',
      body:
          'Synchronization helps your phones play the same audio timeline together. Start with a browser tab or a phone media file, then connect the receiving phones.',
      bullets: [
        'No account required.',
        'Use QR, session code, or nearby discovery.',
        'Audio is sent peer-to-peer after connection.',
      ],
    ),
    _TutorialStep(
      icon: Icons.extension,
      title: 'Browser to phone',
      subtitle: 'Best when audio starts on your computer.',
      body:
          'Open the Chrome extension, choose the tab that is playing audio, then tap Start Streaming. In the app, scan the QR code or enter the session code manually.',
      bullets: [
        'Keep the browser tab open while listening.',
        'Multiple phones can scan the same QR code.',
        'For the best multi-phone experience, mute the browser and listen from the phones.',
      ],
    ),
    _TutorialStep(
      icon: Icons.phone_android,
      title: 'Phone to phone',
      subtitle: 'Best when audio starts on an Android device.',
      body:
          'Pick an audio or video file on the host phone, then let nearby phones join from the Nearby Devices section. You can also scan the host QR code or enter the session manually.',
      bullets: [
        'Grant location for nearby discovery.',
        'Keep devices on the same Wi-Fi or hotspot when possible.',
        'Use the host phone controls to keep everyone aligned.',
      ],
    ),
    _TutorialStep(
      icon: Icons.sync,
      title: 'Why there is a small delay',
      subtitle: 'The delay is there to make phones match each other.',
      body:
          'In browser-to-phone mode, phones intentionally receive a shared delayed feed of about 0.7 seconds. Your computer may be slightly ahead, but connected phones should hear the same moment together.',
      bullets: [
        'This delay is added to sync multiple mobile devices with each other.',
        'Mute the browser audio when phones are your main speakers.',
        'Pause and play from the host when you want a clean resync.',
      ],
    ),
    _TutorialStep(
      icon: Icons.battery_charging_full,
      title: 'For long sessions',
      subtitle: 'A little setup keeps playback steady.',
      body:
          'When listening for a long time, allow the app to keep its audio session active in the background. This helps Android avoid stopping playback when the screen turns off.',
      bullets: [
        'Allow battery optimization exemption if Android asks.',
        'Keep Bluetooth/Wi-Fi stable before starting.',
        'You can reopen this guide anytime from How to use.',
      ],
    ),
  ];

  bool get _isLastStep => _index == _steps.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _close() {
    Navigator.of(context).pop();
  }

  Future<void> _next() async {
    if (_isLastStep) {
      _close();
      return;
    }

    await _controller.nextPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final dialogWidth = size.width < 420 ? size.width - 32 : 420.0;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: dialogWidth,
          maxHeight: size.height * 0.86,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 28,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Quick guide',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _close,
                      child: const Text('Skip'),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _steps.length,
                  onPageChanged: (value) => setState(() => _index = value),
                  itemBuilder: (context, index) => _TutorialStepView(
                    step: _steps[index],
                    stepNumber: index + 1,
                    totalSteps: _steps.length,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        _steps.length,
                        (dotIndex) => AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: dotIndex == _index ? 18 : 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: dotIndex == _index
                                ? AppTheme.accent
                                : AppTheme.textDim.withValues(alpha: 0.32),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _next,
                        icon: Icon(_isLastStep ? Icons.check : Icons.arrow_forward),
                        label: Text(_isLastStep ? 'Finish' : 'Next'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.accent,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TutorialStepView extends StatelessWidget {
  const _TutorialStepView({
    required this.step,
    required this.stepNumber,
    required this.totalSteps,
  });

  final _TutorialStep step;
  final int stepNumber;
  final int totalSteps;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppTheme.accent.withValues(alpha: 0.32)),
            ),
            child: Icon(step.icon, color: AppTheme.accent, size: 30),
          ),
          const SizedBox(height: 18),
          Text(
            'Step $stepNumber of $totalSteps',
            style: const TextStyle(
              color: AppTheme.accent,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            step.title,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              height: 1.12,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            step.subtitle,
            style: const TextStyle(
              color: AppTheme.textDim,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            step.body,
            style: const TextStyle(
              color: AppTheme.textDim,
              fontSize: 14,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 18),
          ...step.bullets.map(
            (bullet) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    margin: const EdgeInsets.only(top: 1),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: const Icon(Icons.check, color: AppTheme.accent, size: 13),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      bullet,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TutorialStep {
  const _TutorialStep({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.body,
    required this.bullets,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String body;
  final List<String> bullets;
}