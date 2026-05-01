import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../theme/app_theme.dart';

/// QR Scanner screen. Returns a `Map<String, String>` with 'id' and 'server'
/// keys when a valid Syncronization QR code is scanned.
class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  bool _scanned = false;

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;

    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;

      // Parse the URL from the QR code
      // Expected format: https://synchronization.netlify.app/?id=XXXX&server=http://...
      try {
        final uri = Uri.parse(raw);
        final sessionId = uri.queryParameters['id'];
        final serverUrl = uri.queryParameters['server'];

        if (sessionId != null && sessionId.isNotEmpty) {
          _scanned = true;
          _controller.stop();
          Navigator.pop(context, {
            'id': sessionId.toUpperCase(),
            'server': serverUrl ?? '',
          });
          return;
        }
      } catch (_) {
        // Not a valid URL, ignore
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Scan QR Code'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on, color: AppTheme.textPrimary),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Camera preview
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),

          // Overlay with cutout
          _buildScanOverlay(),

          // Instructions
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Point at the QR code in the extension popup',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanOverlay() {
    return CustomPaint(
      painter: _ScanOverlayPainter(),
      child: const SizedBox.expand(),
    );
  }
}

class _ScanOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const cutoutSize = 260.0;
    final cutoutLeft = (size.width - cutoutSize) / 2;
    final cutoutTop = (size.height - cutoutSize) / 2 - 40;
    final cutoutRect = Rect.fromLTWH(
      cutoutLeft,
      cutoutTop,
      cutoutSize,
      cutoutSize,
    );

    // Dark overlay
    final overlayPaint = Paint()..color = Colors.black.withValues(alpha: 0.6);
    final fullRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final path = Path()
      ..addRect(fullRect)
      ..addRRect(
        RRect.fromRectAndRadius(cutoutRect, const Radius.circular(20)),
      )
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, overlayPaint);

    // Corner brackets
    const cornerLength = 28.0;
    const cornerWidth = 3.0;
    final cornerPaint = Paint()
      ..color = AppTheme.accent
      ..strokeWidth = cornerWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final corners = [
      // Top-left
      [
        Offset(cutoutLeft, cutoutTop + cornerLength),
        Offset(cutoutLeft, cutoutTop),
        Offset(cutoutLeft + cornerLength, cutoutTop),
      ],
      // Top-right
      [
        Offset(cutoutLeft + cutoutSize - cornerLength, cutoutTop),
        Offset(cutoutLeft + cutoutSize, cutoutTop),
        Offset(cutoutLeft + cutoutSize, cutoutTop + cornerLength),
      ],
      // Bottom-right
      [
        Offset(cutoutLeft + cutoutSize, cutoutTop + cutoutSize - cornerLength),
        Offset(cutoutLeft + cutoutSize, cutoutTop + cutoutSize),
        Offset(cutoutLeft + cutoutSize - cornerLength, cutoutTop + cutoutSize),
      ],
      // Bottom-left
      [
        Offset(cutoutLeft + cornerLength, cutoutTop + cutoutSize),
        Offset(cutoutLeft, cutoutTop + cutoutSize),
        Offset(cutoutLeft, cutoutTop + cutoutSize - cornerLength),
      ],
    ];

    for (final corner in corners) {
      final p = Path()
        ..moveTo(corner[0].dx, corner[0].dy)
        ..lineTo(corner[1].dx, corner[1].dy)
        ..lineTo(corner[2].dx, corner[2].dy);
      canvas.drawPath(p, cornerPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
