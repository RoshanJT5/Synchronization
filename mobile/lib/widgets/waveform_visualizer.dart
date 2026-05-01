import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Animated waveform visualizer shown when audio is playing.
class WaveformVisualizer extends StatefulWidget {
  const WaveformVisualizer({super.key});

  @override
  State<WaveformVisualizer> createState() => _WaveformVisualizerState();
}

class _WaveformVisualizerState extends State<WaveformVisualizer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 80,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, __) {
          return CustomPaint(
            painter: _WaveformPainter(_controller.value),
            size: const Size(double.infinity, 80),
          );
        },
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final double progress;
  static const int barCount = 32;

  _WaveformPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final barWidth = size.width / (barCount * 1.8);
    final spacing = size.width / barCount;
    final centerY = size.height / 2;

    for (int i = 0; i < barCount; i++) {
      final phase = (i / barCount) * math.pi * 2;
      final wave1 = math.sin(phase + progress * math.pi * 2);
      final wave2 = math.sin(phase * 2.3 + progress * math.pi * 3.1);
      final wave3 = math.sin(phase * 0.7 + progress * math.pi * 1.7);
      final combined = (wave1 * 0.5 + wave2 * 0.3 + wave3 * 0.2);
      final barHeight = (combined.abs() * 0.7 + 0.15) * size.height;

      final x = i * spacing + spacing / 2;
      final opacity = 0.4 + combined.abs() * 0.6;

      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppTheme.accent.withValues(alpha: opacity),
            AppTheme.accentDark.withValues(alpha: opacity * 0.6),
          ],
        ).createShader(Rect.fromLTWH(x, 0, barWidth, size.height))
        ..style = PaintingStyle.fill;

      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x, centerY),
          width: barWidth,
          height: barHeight,
        ),
        const Radius.circular(4),
      );
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) => old.progress != progress;
}
