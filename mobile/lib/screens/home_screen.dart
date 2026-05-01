import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../services/webrtc_service.dart';
import '../theme/app_theme.dart';
import '../widgets/gradient_button.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late WebRTCService _webrtc;
  bool _isScanning = false;
  final TextEditingController _urlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _webrtc = Provider.of<WebRTCService>(context, listen: false);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _startScanning() {
    setState(() => _isScanning = true);
  }

  void _stopScanning() {
    setState(() => _isScanning = false);
  }

  void _handleQrCode(BarcodeCapture capture) {
    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      final code = barcode.rawValue;
      if (code != null) {
        debugPrint('[QR] Scanned: $code');
        _stopScanning();
        _connectToSession(code);
        break;
      }
    }
  }

  void _connectToSession(String url) {
    try {
      final uri = Uri.parse(url);
      final sessionId = uri.queryParameters['id'];
      final server = uri.queryParameters['server'] ?? 'https://syncronization-server.onrender.com';

      if (sessionId != null) {
        _webrtc.connect(sessionId, server);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid QR code: Session ID missing')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error parsing QR: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background Gradient
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppTheme.surface,
                  Colors.black,
                ],
              ),
            ),
          ),

          // Main Content
          SafeArea(
            child: Consumer<WebRTCService>(
              builder: (context, webrtc, child) {
                return _buildBody();
              },
            ),
          ),

          // QR Scanner Overlay
          if (_isScanning) _buildScannerOverlay(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final state = _webrtc.state;

    return switch (state) {
      AppConnectionState.idle => _buildIdleView(),
      AppConnectionState.connecting => _buildConnectingView(),
      AppConnectionState.connected => _buildConnectedView(),
      AppConnectionState.error => _buildErrorView(),
    };
  }

  Widget _buildIdleView() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.phonelink_ring,
            size: 80,
            color: AppTheme.accent,
          ),
          const SizedBox(height: 24),
          const Text(
            'Syncronization',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Scan the QR code on your computer to start streaming audio.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 48),
          GradientButton(
            label: 'Scan QR Code',
            icon: Icons.qr_code_scanner,
            onPressed: _startScanning,
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: _showManualDialog,
            child: const Text(
              'Enter URL manually',
              style: TextStyle(color: AppTheme.accent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: AppTheme.accent),
          const SizedBox(height: 24),
          const Text(
            'Connecting...',
            style: TextStyle(
              fontSize: 20,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Joining session ${_webrtc.activeSessionId}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 48),
          TextButton(
            onPressed: () => _webrtc.disconnect(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectedView() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildConnectionQualityIndicator(),
          const SizedBox(height: 20),
          _buildPulsingIcon(),
          const SizedBox(height: 32),
          const Text(
            'Connected & Streaming',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppTheme.accent,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Audio is playing through your phone speaker.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 32),
          // Volume Control
          Row(
            children: [
              const Icon(Icons.volume_down, color: Colors.white54, size: 20),
              Expanded(
                child: Slider(
                  value: _webrtc.volume,
                  activeColor: AppTheme.accent,
                  inactiveColor: Colors.white10,
                  onChanged: (v) => _webrtc.setVolume(v),
                ),
              ),
              const Icon(Icons.volume_up, color: Colors.white54, size: 20),
            ],
          ),
          const SizedBox(height: 48),
          GradientButton(
            label: 'Disconnect',
            icon: Icons.link_off,
            colors: const [Colors.redAccent, Color(0xFF8B0000)],
            onPressed: () => _webrtc.disconnect(),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            size: 80,
            color: Colors.redAccent,
          ),
          const SizedBox(height: 24),
          const Text(
            'Connection Failed',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _webrtc.errorMessage,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.redAccent.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 48),
          GradientButton(
            label: 'Try Again',
            icon: Icons.refresh,
            onPressed: () => _webrtc.disconnect(),
          ),
        ],
      ),
    );
  }

  Widget _buildScannerOverlay() {
    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          MobileScanner(
            onDetect: _handleQrCode,
          ),
          // Scanner UI overlay
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white, size: 30),
                        onPressed: _stopScanning,
                      ),
                      const Expanded(
                        child: Text(
                          'Scan QR Code',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 48), // Spacer to center title
                    ],
                  ),
                ),
                const Spacer(),
                Container(
                  width: 250,
                  height: 250,
                  decoration: BoxDecoration(
                    border: Border.all(color: AppTheme.accent, width: 4),
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                const Spacer(),
                const Padding(
                  padding: EdgeInsets.only(bottom: 48),
                  child: Text(
                    'Align QR code within the frame',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPulsingIcon() {
    // This is a simplified pulsing effect for demo
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppTheme.accent.withValues(alpha: 0.1),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.2), width: 2),
      ),
      child: const Icon(
        Icons.volume_up,
        size: 80,
        color: AppTheme.accent,
      ),
    );
  }

  Widget _buildConnectionQualityIndicator() {
    final quality = _webrtc.connectionQuality;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 500),
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _qualityColor(quality),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _qualityLabel(quality),
          style: TextStyle(
            fontSize: 10,
            color: _qualityColor(quality),
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }

  Color _qualityColor(ConnectionQuality q) {
    return switch (q) {
      ConnectionQuality.excellent => AppTheme.green,
      ConnectionQuality.good => Colors.amber,
      ConnectionQuality.poor => Colors.redAccent,
      ConnectionQuality.unknown => Colors.white24,
    };
  }

  String _qualityLabel(ConnectionQuality q) {
    return switch (q) {
      ConnectionQuality.excellent => 'EXCELLENT SIGNAL',
      ConnectionQuality.good => 'GOOD SIGNAL',
      ConnectionQuality.poor => 'POOR SIGNAL',
      ConnectionQuality.unknown => 'MEASURING...',
    };
  }

  void _showManualDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Enter Connection URL', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: _urlController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'syncronization://connect?id=...',
            hintStyle: TextStyle(color: Colors.white38),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.accent)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () {
              final url = _urlController.text;
              if (url.isNotEmpty) {
                _connectToSession(url);
                Navigator.pop(context);
              }
            },
            child: const Text('Connect', style: TextStyle(color: AppTheme.accent)),
          ),
        ],
      ),
    );
  }
}
