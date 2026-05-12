import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../services/webrtc_service.dart';
import '../services/discovery_service.dart';
import '../services/mobile_source_service.dart';
import '../services/sync_playback_engine.dart';
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
  late MobileSourceService _source;
  bool _isScanning = false;
  final TextEditingController _urlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _webrtc = Provider.of<WebRTCService>(context, listen: false);
    _discovery = Provider.of<DiscoveryService>(context, listen: false);
    _source = Provider.of<MobileSourceService>(context, listen: false);
    if (widget.enableDiscovery) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _discovery.startDiscovery();
      });
    }
    _webrtc.addListener(_onWebrtcStateChanged);
    _source.addListener(_onSourceStateChanged);
  }

  void _onWebrtcStateChanged() {
    if (_webrtc.state == AppConnectionState.idle &&
        widget.enableDiscovery &&
        !_discovery.isConnected &&
        !_discovery.isConnecting) {
      _discovery.startDiscovery();
    }
  }

  void _onSourceStateChanged() {
    // When source stops, restart discovery
    if (_source.state == MobileSourceState.idle &&
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
    _source.removeListener(_onSourceStateChanged);
    _urlController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        widget.enableDiscovery &&
        !_discovery.isConnected &&
        !_discovery.isConnecting &&
        _webrtc.state == AppConnectionState.idle &&
        _source.state == MobileSourceState.idle) {
      _discovery.startDiscovery();
    }
  }

  void _startScanning() => setState(() => _isScanning = true);
  void _stopScanning() => setState(() => _isScanning = false);

  void _handleQrCode(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final code = barcode.rawValue;
      if (code != null) {
        _stopScanning();
        _connectToSession(code);
        break;
      }
    }
  }

  void _connectToSession(String input) {
    try {
      String sessionId;
      String server = 'https://synchronization-807q.onrender.com';
      if (input.startsWith('http')) {
        final uri = Uri.parse(input);
        final pathId = uri.pathSegments.length >= 2 &&
                uri.pathSegments.first == 'c'
            ? uri.pathSegments[1]
            : null;
        sessionId = uri.queryParameters['id'] ?? pathId ?? '';
        server = uri.queryParameters['server'] ?? server;
      } else {
        sessionId = input;
      }
      if (sessionId.isNotEmpty) {
        _discovery.stopDiscovery();
        _webrtc.connect(sessionId.toUpperCase(), server);
      } else {
        _showSnack('Invalid input: Session ID missing');
      }
    } catch (e) {
      _showSnack('Error: $e');
    }
  }

  void _connectDiscovered(DiscoveredSession session) {
    _discovery.stopDiscovery();
    _webrtc.connect(
      session.sessionId,
      'https://synchronization-807q.onrender.com',
    );
  }

  void _showSnack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  //  Build 

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
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
            child: Consumer2<WebRTCService, MobileSourceService>(
              builder: (context, webrtc, source, _) => _buildBody(),
            ),
          ),
          if (_isScanning) _buildScannerOverlay(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    // Source phone is streaming
    if (_source.state == MobileSourceState.streaming ||
        _source.state == MobileSourceState.announcing) {
      return _buildSourceStreamingView();
    }
    if (_source.state == MobileSourceState.error) {
      return _buildSourceErrorView();
    }
    // Receiver states
    return switch (_webrtc.state) {
      AppConnectionState.idle => _buildIdleView(),
      AppConnectionState.connecting => _buildConnectingView(),
      AppConnectionState.connected => _buildConnectedView(),
      AppConnectionState.error => _buildErrorView(),
    };
  }

  //  Idle 

  Widget _buildIdleView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 32),

          //  NEARBY COMPUTERS 
          _buildSectionLabel('NEARBY COMPUTERS', Icons.laptop_outlined),
          const SizedBox(height: 10),
          _buildComputerDiscovery(),

          const SizedBox(height: 24),

          //  NEARBY PHONES 
          _buildSectionLabel('NEARBY PHONES', Icons.smartphone_outlined),
          const SizedBox(height: 10),
          _buildMobileDiscovery(),

          const SizedBox(height: 28),
          _buildDivider(),
          const SizedBox(height: 24),

          //  Stream from this phone 
          _buildStreamFromPhoneButton(),

          const SizedBox(height: 16),
          _buildDivider(),
          const SizedBox(height: 20),

          //  QR / manual fallback 
          GradientButton(
            label: 'Scan QR Code',
            icon: Icons.qr_code_scanner,
            onPressed: _startScanning,
          ),
          const SizedBox(height: 12),
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

  Widget _buildHeader() {
    return Row(
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
    );
  }

  Widget _buildSectionLabel(String label, IconData icon) {
    return Consumer<DiscoveryService>(
      builder: (context, discovery, _) => Row(
        children: [
          Icon(icon, size: 13, color: AppTheme.textDim),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: AppTheme.textDim,
              letterSpacing: 1.5,
            ),
          ),
          const Spacer(),
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
                ? 'Live'
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
    );
  }

  Widget _buildDivider() {
    return Row(
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
    );
  }

  Widget _buildComputerDiscovery() {
    return Consumer<DiscoveryService>(
      builder: (context, discovery, _) {
        final sessions = discovery.computerSessions;
        if (sessions.isEmpty) {
          return _buildEmptyCard(
            icon: Icons.laptop_outlined,
            title: discovery.isConnecting
                ? 'Looking for computers...'
                : 'No computers found',
            subtitle: 'Open the Chrome extension\nto appear here automatically.',
            discovery: discovery,
          );
        }
        return Column(
          children: sessions.map((s) => _buildSessionCard(s)).toList(),
        );
      },
    );
  }

  Widget _buildMobileDiscovery() {
    return Consumer<DiscoveryService>(
      builder: (context, discovery, _) {
        final sessions = discovery.mobileSessions;
        if (sessions.isEmpty) {
          return _buildEmptyCard(
            icon: Icons.smartphone_outlined,
            title: discovery.isConnecting
                ? 'Looking for phones...'
                : 'No phones found',
            subtitle: 'Tap "Stream from this Phone"\non another device to appear here.',
            discovery: discovery,
            showRetry: false,
          );
        }
        return Column(
          children: sessions.map((s) => _buildSessionCard(s)).toList(),
        );
      },
    );
  }

  Widget _buildEmptyCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required DiscoveryService discovery,
    bool showRetry = true,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 20),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          Icon(icon, size: 36, color: Colors.white.withValues(alpha: 0.12)),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              color: AppTheme.textDim,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.25),
              fontSize: 11,
            ),
          ),
          if (showRetry && !discovery.isConnecting && !discovery.isConnected) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => discovery.startDiscovery(),
              icon: const Icon(Icons.refresh, size: 14, color: AppTheme.accent),
              label: const Text(
                'Retry',
                style: TextStyle(color: AppTheme.accent, fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSessionCard(DiscoveredSession session) {
    final isMobile = session.isMobileSource;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _connectDiscovered(session),
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: AppTheme.accent.withValues(alpha: 0.25),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.accent.withValues(alpha: 0.05),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isMobile ? Icons.smartphone : Icons.laptop,
                    color: AppTheme.accent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
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
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(
                    Icons.arrow_forward_rounded,
                    color: AppTheme.accent,
                    size: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStreamFromPhoneButton() {
    return GestureDetector(
      onTap: () async {
        _discovery.stopDiscovery();
        await _source.startSource();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.accent.withValues(alpha: 0.15),
              AppTheme.accentDark.withValues(alpha: 0.15),
            ],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.accent, AppTheme.accentDark],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.mic, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Stream from this Phone',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Use mic audio  other phones listen',
                    style: TextStyle(
                      color: AppTheme.textDim,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppTheme.accent,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  //  Source: streaming from this phone 

  Widget _buildSourceStreamingView() {
    return Consumer<MobileSourceService>(
      builder: (context, source, _) {
        final isAnnouncing = source.state == MobileSourceState.announcing;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Mic icon with pulse ring
              Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 800),
                    width: isAnnouncing ? 100 : 120,
                    height: isAnnouncing ? 100 : 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.accent.withValues(alpha: 0.08),
                      border: Border.all(
                        color: AppTheme.accent.withValues(alpha: 0.2),
                        width: 2,
                      ),
                    ),
                  ),
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [AppTheme.accent, AppTheme.accentDark],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.accent.withValues(alpha: 0.4),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.mic, color: Colors.white, size: 32),
                  ),
                ],
              ),

              const SizedBox(height: 28),

              Text(
                isAnnouncing ? 'Ready to Stream' : 'Streaming Live',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isAnnouncing
                    ? 'Waiting for speakers to connect'
                    : 'Mic audio is playing on connected phones.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ),

              const SizedBox(height: 24),

              // Session ID badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.accent.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.tag, size: 14, color: AppTheme.textDim),
                    const SizedBox(width: 6),
                    Text(
                      source.sessionId,
                      style: const TextStyle(
                        color: AppTheme.accent,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'monospace',
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Speaker count
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: source.speakerCount > 0
                    ? Container(
                        key: ValueKey(source.speakerCount),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppTheme.green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.green.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppTheme.green,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${source.speakerCount} phone${source.speakerCount == 1 ? '' : 's'} connected',
                              style: const TextStyle(
                                color: AppTheme.green,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      )
                    : Container(
                        key: const ValueKey('none'),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha: 0.2),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'No speakers yet',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.4),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),

              const SizedBox(height: 40),

              GradientButton(
                label: 'Stop Streaming',
                icon: Icons.stop_rounded,
                colors: const [Colors.redAccent, Color(0xFF8B0000)],
                onPressed: () async {
                  await _source.stopSource();
                  if (mounted && widget.enableDiscovery) {
                    _discovery.startDiscovery();
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSourceErrorView() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.mic_off, size: 72, color: Colors.redAccent),
          const SizedBox(height: 24),
          const Text(
            'Stream Failed',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _source.errorMessage,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.redAccent.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 40),
          GradientButton(
            label: 'Try Again',
            icon: Icons.refresh,
            onPressed: () async {
              await _source.stopSource();
              await _source.startSource();
            },
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () async {
              await _source.stopSource();
              if (mounted && widget.enableDiscovery) {
                _discovery.startDiscovery();
              }
            },
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppTheme.textDim),
            ),
          ),
        ],
      ),
    );
  }

  //  Receiver: connecting 

  Widget _buildConnectingView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: _webrtc.isWaitingForHost
                  ? Container(
                      key: const ValueKey('waiting'),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.accent.withValues(alpha: 0.1),
                        border: Border.all(
                          color: AppTheme.accent.withValues(alpha: 0.3),
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.laptop_mac,
                        size: 48,
                        color: AppTheme.accent,
                      ),
                    )
                  : const SizedBox(
                      key: ValueKey('spinner'),
                      width: 48,
                      height: 48,
                      child: CircularProgressIndicator(
                        color: AppTheme.accent,
                        strokeWidth: 3,
                      ),
                    ),
            ),
            const SizedBox(height: 28),
            Text(
              _webrtc.isWaitingForHost ? 'Ready to Connect' : 'Connecting...',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _webrtc.isWaitingForHost
                  ? 'Now click "Start Streaming"\non the source device.'
                  : 'Joining session ${_webrtc.activeSessionId}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: Colors.white.withValues(alpha: 0.55),
                height: 1.5,
              ),
            ),
            if (_webrtc.isWaitingForHost) ...[
              const SizedBox(height: 24),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppTheme.accent.withValues(alpha: 0.25)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.accent,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Session ${_webrtc.activeSessionId}',
                      style: const TextStyle(
                        color: AppTheme.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'monospace',
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
      ),
    );
  }

  //  Receiver: connected 

  Widget _buildConnectedView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Column(
        children: [
          _buildConnectionQualityIndicator(),
          const SizedBox(height: 20),
          _buildPulsingIcon(),
          const SizedBox(height: 28),
          const Text(
            'Connected & Streaming',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: AppTheme.accent,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _webrtc.isSynced
                ? '🔄 Sync: Active  |  Buffer: 700ms'
                : '⏳ Syncing clock...',
            style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Text(
            'Audio is playing through your phone speaker.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 24),
          _buildSyncStatsCard(),
          const SizedBox(height: 16),
          _buildSyncSettingsCard(),
          const SizedBox(height: 20),
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
              const SizedBox(width: 8),
              SizedBox(
                width: 35,
                child: Text(
                  '${(_webrtc.volume * 100).toInt()}%',
                  style: const TextStyle(
                    color: AppTheme.textDim,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
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

  Widget _buildSyncStatsCard() {
    return ListenableBuilder(
      listenable: _webrtc.clockSync,
      builder: (context, _) {
        final latency = _webrtc.clockSync.emaLatencyMs;
        final jitter = _webrtc.clockSync.emaJitterMs;
        Color syncColor;
        String syncLabel;
        if (latency < 30 && jitter < 5) {
          syncColor = AppTheme.green;
          syncLabel = 'PERFECT SYNC';
        } else if (latency < 60 && jitter < 15) {
          syncColor = Colors.amber;
          syncLabel = 'GOOD SYNC';
        } else {
          syncColor = Colors.redAccent;
          syncLabel = 'SYNCING...';
        }
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: syncColor.withValues(alpha: 0.25)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _statCell('LATENCY', '${latency.toStringAsFixed(0)}ms', syncColor),
                  Container(width: 1, height: 28, color: AppTheme.border),
                  _statCell('JITTER', '${jitter.toStringAsFixed(0)}ms', syncColor),
                  Container(width: 1, height: 28, color: AppTheme.border),
                  _statCell('SYNC', syncLabel, syncColor),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _webrtc.syncStats,
                style: const TextStyle(
                  color: AppTheme.textDim,
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSyncSettingsCard() {
    return ListenableBuilder(
      listenable: _webrtc.syncEngine,
      builder: (context, _) {
        final engine = _webrtc.syncEngine;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'SYNCHRONIZATION',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: engine.syncQuality == SyncQuality.synced 
                        ? AppTheme.green.withValues(alpha: 0.1) 
                        : Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      engine.syncQuality.label,
                      style: TextStyle(
                        color: engine.syncQuality == SyncQuality.synced 
                          ? AppTheme.green 
                          : Colors.orange,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ...SyncMode.values.map((m) {
                final isSelected = engine.mode == m;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () => engine.setMode(m),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isSelected ? AppTheme.accent.withValues(alpha: 0.1) : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected ? AppTheme.accent.withValues(alpha: 0.3) : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                            color: isSelected ? AppTheme.accent : AppTheme.textDim,
                            size: 18,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  m.label,
                                  style: TextStyle(
                                    color: isSelected ? Colors.white : AppTheme.textDim,
                                    fontSize: 13,
                                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  m.description,
                                  style: TextStyle(
                                    color: AppTheme.textDim.withValues(alpha: 0.6),
                                    fontSize: 10,
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
              }).toList(),
            ],
          ),
        );
      },
    );
  }

  Widget _statCell(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.textDim,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }

  //  Receiver: error 

  Widget _buildErrorView() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 72, color: Colors.redAccent),
          const SizedBox(height: 24),
          const Text(
            'Connection Failed',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _webrtc.errorMessage,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.redAccent.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 40),
          GradientButton(
            label: 'Try Again',
            icon: Icons.refresh,
            onPressed: () => _webrtc.disconnect(),
          ),
        ],
      ),
    );
  }

  //  QR Scanner overlay 

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
                        icon: const Icon(Icons.close,
                            color: Colors.white, size: 30),
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

  //  Helpers 

  Widget _buildPulsingIcon() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppTheme.accent.withValues(alpha: 0.1),
        border: Border.all(
            color: AppTheme.accent.withValues(alpha: 0.2), width: 2),
      ),
      child: const Icon(Icons.volume_up, size: 72, color: AppTheme.accent),
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
            hintText: 'e.g. A1B2C3',
            hintStyle: TextStyle(color: Colors.white38),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: AppTheme.accent),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () {
              final url = _urlController.text;
              if (url.isNotEmpty) {
                _connectToSession(url);
                Navigator.pop(context);
              }
            },
            child: const Text('Connect',
                style: TextStyle(color: AppTheme.accent)),
          ),
        ],
      ),
    );
  }
}
