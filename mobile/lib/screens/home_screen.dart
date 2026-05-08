import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../services/webrtc_service.dart';
import '../services/discovery_service.dart';
import '../theme/app_theme.dart';
import '../widgets/gradient_button.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.enableDiscovery = true});

  final bool enableDiscovery;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late WebRTCService _webrtc;
  late DiscoveryService _discovery;
  bool _isScanning = false;
  final TextEditingController _urlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _webrtc = Provider.of<WebRTCService>(context, listen: false);
    _discovery = Provider.of<DiscoveryService>(context, listen: false);
    // Start auto-discovery after the first frame so provider notifications do
    // not fire while Flutter is still building the app shell.
    if (widget.enableDiscovery) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _discovery.startDiscovery();
        }
      });
    }
    // Restart discovery when WebRTC goes back to idle (disconnect/error→try again)
    _webrtc.addListener(_onWebrtcStateChanged);
  }

  void _onWebrtcStateChanged() {
    if (_webrtc.state == AppConnectionState.idle &&
        widget.enableDiscovery &&
        !_discovery.isConnected &&
        !_discovery.isConnecting) {
      _discovery.startDiscovery();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _webrtc.removeListener(_onWebrtcStateChanged);
    _urlController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Re-start discovery when app comes back to foreground
      if (widget.enableDiscovery &&
          !_discovery.isConnected &&
          !_discovery.isConnecting) {
        _discovery.startDiscovery();
      }
    }
  }

  void _startScanning() => setState(() => _isScanning = true);
  void _stopScanning() => setState(() => _isScanning = false);

  void _handleQrCode(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final code = barcode.rawValue;
      if (code != null) {
        debugPrint('[QR] Scanned: $code');
        _stopScanning();
        _connectToSession(code);
        break;
      }
    }
  }

  void _connectToSession(String input) {
    try {
      String sessionId;
      String server = 'https://synchronization-5865.onrender.com';

      if (input.startsWith('http')) {
        final uri = Uri.parse(input);
        sessionId = uri.queryParameters['id'] ?? '';
        server = uri.queryParameters['server'] ?? server;
      } else {
        sessionId = input;
      }

      if (sessionId.isNotEmpty) {
        _discovery.stopDiscovery(); // FREE the socket before WebRTC connects
        _webrtc.connect(sessionId.toUpperCase(), server);
      } else {
        _showSnack('Invalid input: Session ID missing');
      }
    } catch (e) {
      _showSnack('Error parsing input: $e');
    }
  }

  void _connectDiscovered(DiscoveredSession session) {
    _discovery.stopDiscovery(); // FREE the socket before WebRTC connects
    _webrtc.connect(
      session.sessionId,
      'https://synchronization-5865.onrender.com',
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppTheme.surface, Colors.black],
              ),
            ),
          ),

          SafeArea(
            child: Consumer<WebRTCService>(
              builder: (context, webrtc, _) => _buildBody(),
            ),
          ),

          if (_isScanning) _buildScannerOverlay(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return switch (_webrtc.state) {
      AppConnectionState.idle => _buildIdleView(),
      AppConnectionState.connecting => _buildConnectingView(),
      AppConnectionState.connected => _buildConnectedView(),
      AppConnectionState.error => _buildErrorView(),
    };
  }

  // ── Idle: auto-discovery list + QR fallback ────────────────────────────────

  Widget _buildIdleView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppTheme.accent, AppTheme.accentDark],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.speaker, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              const Text(
                'Syncronization',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),

          const SizedBox(height: 36),

          // ── Auto-discovery section ──────────────────────────────────────
          _buildDiscoverySection(),

          const SizedBox(height: 32),

          // ── Divider ─────────────────────────────────────────────────────
          Row(
            children: [
              const Expanded(child: Divider(color: AppTheme.border)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'OR',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              const Expanded(child: Divider(color: AppTheme.border)),
            ],
          ),

          const SizedBox(height: 28),

          // ── QR scan fallback ─────────────────────────────────────────────
          GradientButton(
            label: 'Scan QR Code',
            icon: Icons.qr_code_scanner,
            onPressed: _startScanning,
          ),

          const SizedBox(height: 14),

          Center(
            child: TextButton(
              onPressed: _showManualDialog,
              child: const Text(
                'Enter Session ID manually',
                style: TextStyle(color: AppTheme.accent, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscoverySection() {
    return Consumer<DiscoveryService>(
      builder: (context, discovery, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section header
            Row(
              children: [
                const Text(
                  'NEARBY COMPUTERS',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textDim,
                    letterSpacing: 1.5,
                  ),
                ),
                const Spacer(),
                // Connection status dot
                AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: discovery.isConnected
                        ? AppTheme.green
                        : discovery.isConnecting
                            ? Colors.amber
                            : Colors.white24,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  discovery.isConnected
                      ? 'Listening'
                      : discovery.isConnecting
                          ? 'Connecting...'
                          : 'Offline',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppTheme.textDim,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Session list or empty state
            if (discovery.sessions.isEmpty)
              _buildEmptyDiscovery(discovery)
            else
              ...discovery.sessions.map(_buildSessionCard),
          ],
        );
      },
    );
  }

  Widget _buildEmptyDiscovery(DiscoveryService discovery) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          Icon(
            Icons.laptop_outlined,
            size: 40,
            color: Colors.white.withValues(alpha: 0.15),
          ),
          const SizedBox(height: 12),
          Text(
            discovery.isConnecting
                ? 'Looking for computers...'
                : 'No computers found',
            style: const TextStyle(
              color: AppTheme.textDim,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Open the Chrome extension and click\n"Start Streaming" to appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.3),
              fontSize: 12,
            ),
          ),
          if (!discovery.isConnecting && !discovery.isConnected) ...[
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () => discovery.startDiscovery(),
              icon: const Icon(Icons.refresh, size: 16, color: AppTheme.accent),
              label: const Text(
                'Retry',
                style: TextStyle(color: AppTheme.accent, fontSize: 13),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSessionCard(DiscoveredSession session) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _connectDiscovered(session),
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppTheme.accent.withValues(alpha: 0.25)),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.accent.withValues(alpha: 0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                // Icon
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.laptop,
                    color: AppTheme.accent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                // Label + session ID
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Session ${session.sessionId}',
                        style: const TextStyle(
                          color: AppTheme.textDim,
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                // Connect arrow
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.arrow_forward_rounded,
                    color: AppTheme.accent,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Connecting ─────────────────────────────────────────────────────────────

  Widget _buildConnectingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: AppTheme.accent),
          const SizedBox(height: 24),
          const Text(
            'Connecting...',
            style: TextStyle(fontSize: 20, color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(
            'Joining session ${_webrtc.activeSessionId}',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
          ),
          const SizedBox(height: 48),
          TextButton(
            onPressed: () => _webrtc.disconnect(),
            child: const Text('Cancel', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  // ── Connected ──────────────────────────────────────────────────────────────

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
          // Volume slider
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

  // ── Error ──────────────────────────────────────────────────────────────────

  Widget _buildErrorView() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 80, color: Colors.redAccent),
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

  // ── QR Scanner overlay ─────────────────────────────────────────────────────

  Widget _buildScannerOverlay() {
    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          MobileScanner(onDetect: _handleQrCode),
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
                      const SizedBox(width: 48),
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

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _buildPulsingIcon() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppTheme.accent.withValues(alpha: 0.1),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.2), width: 2),
      ),
      child: const Icon(Icons.volume_up, size: 80, color: AppTheme.accent),
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

  Color _qualityColor(ConnectionQuality q) => switch (q) {
        ConnectionQuality.excellent => AppTheme.green,
        ConnectionQuality.good => Colors.amber,
        ConnectionQuality.poor => Colors.redAccent,
        ConnectionQuality.unknown => Colors.white24,
      };

  String _qualityLabel(ConnectionQuality q) => switch (q) {
        ConnectionQuality.excellent => 'EXCELLENT SIGNAL',
        ConnectionQuality.good => 'GOOD SIGNAL',
        ConnectionQuality.poor => 'POOR SIGNAL',
        ConnectionQuality.unknown => 'MEASURING...',
      };

  void _showManualDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text(
          'Enter Session ID',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: _urlController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'e.g. A1B2C3D4',
            hintStyle: TextStyle(color: Colors.white38),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: AppTheme.accent),
            ),
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
