import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:synchronization/services/discovery_service.dart';
import 'package:synchronization/services/file_service.dart';
import 'package:synchronization/services/guest_session_controller.dart';
import 'package:synchronization/services/host_media_player.dart';
import 'package:synchronization/services/host_session_controller.dart';
import 'package:synchronization/services/webrtc_service.dart';
import 'package:synchronization/theme/app_theme.dart';
import 'package:video_player/video_player.dart';

enum _ScreenMode { welcome, hostSetup, hostActive, guestJoin, guestActive }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.enableDiscovery = true});

  final bool enableDiscovery;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FileService _fileService = FileService();
  final TextEditingController _codeController = TextEditingController();

  _ScreenMode _mode = _ScreenMode.welcome;
  HostSessionController? _hostController;
  GuestSessionController? _guestController;
  PlatformFile? _selectedFile;
  HostPlaybackMode _hostPlaybackMode = HostPlaybackMode.audioOnly;
  bool _isScanning = false;
  bool _isBusy = false;
  bool _isFullscreen = false;
  double _volume = 1.0;

  @override
  void initState() {
    super.initState();
    if (widget.enableDiscovery) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.read<DiscoveryService>().startDiscovery();
      });
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final file = await _fileService.pickMediaFile();
    if (file == null) return;
    setState(() {
      _selectedFile = file;
      if (!_isVideoFile(file)) _hostPlaybackMode = HostPlaybackMode.audioOnly;
    });
  }

  Future<void> _startHostSession() async {
    final file = _selectedFile;
    if (file == null) {
      _showSnack('Pick a file first');
      return;
    }

    setState(() => _isBusy = true);
    try {
      final controller = HostSessionController();
      await controller.setupSession(file, playbackMode: _hostPlaybackMode);
      controller.startPeriodicSync();
      if (!mounted) return;

      final webrtc = context.read<WebRTCService>();
      context.read<DiscoveryService>().stopDiscovery();
      webrtc.initializeHost(controller);
      await webrtc.createHostSession();
      setState(() {
        _hostController = controller;
        _mode = _ScreenMode.hostActive;
      });
    } catch (e) {
      _showSnack(e.toString());
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _joinSession(String input) async {
    final sessionId = _parseSessionId(input);
    if (sessionId.isEmpty) {
      _showSnack('Enter a valid session code');
      return;
    }

    setState(() => _isBusy = true);
    try {
      final controller = GuestSessionController();
      if (!mounted) return;
      final webrtc = context.read<WebRTCService>();
      context.read<DiscoveryService>().stopDiscovery();
      webrtc.initializeGuest(controller);
      await webrtc.connect(sessionId);
      setState(() {
        _guestController = controller;
        _mode = _ScreenMode.guestActive;
      });
    } catch (e) {
      _showSnack(e.toString());
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void _handleQrCode(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final code = barcode.rawValue;
      if (code != null) {
        setState(() => _isScanning = false);
        _codeController.text = _parseSessionId(code);
        _joinSession(code);
        break;
      }
    }
  }

  String _parseSessionId(String input) {
    try {
      if (!input.startsWith('http')) return input.trim().toUpperCase();
      final uri = Uri.parse(input);
      final pathId =
          uri.pathSegments.length >= 2 && uri.pathSegments.first == 'c'
              ? uri.pathSegments[1]
              : null;
      return (uri.queryParameters['id'] ?? pathId ?? '').trim().toUpperCase();
    } catch (_) {
      return input.trim().toUpperCase();
    }
  }

  void _leaveSession() {
    context.read<WebRTCService>().disconnect();
    setState(() {
      _mode = _ScreenMode.welcome;
      _hostController = null;
      _guestController = null;
      _selectedFile = null;
      _hostPlaybackMode = HostPlaybackMode.audioOnly;
      _codeController.clear();
    });
    if (widget.enableDiscovery) {
      context.read<DiscoveryService>().startDiscovery();
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  bool _isVideoFile(PlatformFile file) {
    final name = file.name.toLowerCase();
    return ['.mp4', '.mkv', '.avi', '.mov'].any(name.endsWith);
  }

  void _enterFullscreen() {
    setState(() => _isFullscreen = true);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  void _exitFullscreen() {
    setState(() => _isFullscreen = false);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppTheme.surface, AppTheme.bg],
              ),
            ),
            child: SizedBox.expand(),
          ),
          SafeArea(
            child: Consumer<WebRTCService>(
              builder: (context, webrtc, _) => AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: switch (_mode) {
                  _ScreenMode.welcome => _buildWelcome(),
                  _ScreenMode.hostSetup => _buildHostSetup(webrtc),
                  _ScreenMode.hostActive => _buildHostActive(webrtc),
                  _ScreenMode.guestJoin => _buildGuestJoin(webrtc),
                  _ScreenMode.guestActive => _buildGuestActive(webrtc),
                },
              ),
            ),
          ),
          if (_isScanning) _buildScannerOverlay(),
          if (_isFullscreen && _hostController != null)
            _FullscreenVideoOverlay(
              controller: _hostController!,
              onExit: _exitFullscreen,
            ),
        ],
      ),
    );
  }

  Widget _buildWelcome() {
    return _Page(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          const Icon(Icons.graphic_eq, color: AppTheme.accent, size: 64),
          const SizedBox(height: 20),
          const Text(
            'Synchronization',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'LAN stream sync for phones',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textDim, fontSize: 14),
          ),
          const Spacer(),
          _PrimaryButton(
            label: 'HOST A SESSION',
            icon: Icons.music_note,
            onPressed: () => setState(() => _mode = _ScreenMode.hostSetup),
          ),
          const SizedBox(height: 14),
          _SecondaryButton(
            label: 'JOIN A SESSION',
            icon: Icons.smartphone,
            onPressed: () => setState(() => _mode = _ScreenMode.guestJoin),
          ),
        ],
      ),
    );
  }

  Widget _buildHostSetup(WebRTCService webrtc) {
    return _Page(
      title: 'HOST SETUP',
      onBack: () => setState(() => _mode = _ScreenMode.welcome),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 18),
          const Text(
            'Step 1: Pick your audio/video file',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          _FileCard(file: _selectedFile),
          if (_selectedFile != null && _isVideoFile(_selectedFile!)) ...[
            const SizedBox(height: 18),
            _PlaybackModePicker(
              value: _hostPlaybackMode,
              onChanged: (mode) => setState(() => _hostPlaybackMode = mode),
            ),
          ],
          const SizedBox(height: 18),
          _SecondaryButton(
            label: 'PICK FILE',
            icon: Icons.folder_open,
            onPressed: _pickFile,
          ),
          const SizedBox(height: 18),
          const _InfoCard(
            text:
                'Guests must be on the same WiFi as this phone, or connected to this phone hotspot.',
          ),
          const Spacer(),
          _PrimaryButton(
            label: _isBusy ? 'STARTING...' : 'START SESSION',
            icon: Icons.rocket_launch,
            onPressed:
                _isBusy || _selectedFile == null ? null : _startHostSession,
          ),
          if (webrtc.state == AppConnectionState.error) ...[
            const SizedBox(height: 12),
            Text(webrtc.errorMessage,
                style: const TextStyle(color: AppTheme.red)),
          ],
        ],
      ),
    );
  }

  Widget _buildHostActive(WebRTCService webrtc) {
    final controller = _hostController ?? webrtc.hostController;
    return _Page(
      title: 'SESSION ACTIVE',
      onBack: _leaveSession,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatusPill(
            icon: Icons.group,
            text: '${webrtc.guestCount} guests connected',
          ),
          const SizedBox(height: 16),
          _QrPanel(sessionId: webrtc.activeSessionId),
          const SizedBox(height: 16),
          if (controller != null)
            _HostPlayerPanel(
              controller: controller,
              onSeek: (ms) => controller.seekTo(ms),
              onFullscreen: controller.isVideoPlayback ? _enterFullscreen : null,
            ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _RoundButton(
                icon: Icons.replay_10,
                onPressed: controller == null
                    ? null
                    : () => controller.seekTo(
                          (controller.position.inMilliseconds - 10000)
                              .clamp(0, 1 << 31),
                        ),
              ),
              const SizedBox(width: 18),
              _RoundButton(
                icon: controller?.isPlaying == true
                    ? Icons.pause
                    : Icons.play_arrow,
                large: true,
                onPressed: controller == null
                    ? null
                    : () {
                        controller.isPlaying
                            ? controller.pause()
                            : controller.play();
                        setState(() {});
                      },
              ),
              const SizedBox(width: 18),
              _RoundButton(
                icon: Icons.forward_10,
                onPressed: controller == null
                    ? null
                    : () => controller.seekTo(
                          controller.position.inMilliseconds + 10000,
                        ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _VolumeSlider(
            value: _volume,
            onChanged: (value) {
              setState(() => _volume = value);
              webrtc.setVolume(value);
            },
          ),
          const SizedBox(height: 14),
          const _StatusPill(
              icon: Icons.settings_input_antenna, text: 'Stream: Active'),
          const Spacer(),
          _SecondaryButton(
            label: 'END SESSION',
            icon: Icons.link_off,
            danger: true,
            onPressed: _leaveSession,
          ),
        ],
      ),
    );
  }

  Widget _buildGuestJoin(WebRTCService webrtc) {
    final discovery = context.watch<DiscoveryService>();
    return _Page(
      title: 'JOIN SESSION',
      onBack: () => setState(() => _mode = _ScreenMode.welcome),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 18),
          _DiscoveredSessions(
            sessions: discovery.sessions,
            isLoading: discovery.isConnecting,
            onRefresh: () => discovery.startDiscovery(),
            onJoin: (session) {
              _codeController.text = session.sessionId;
              _joinSession(session.sessionId);
            },
          ),
          const SizedBox(height: 18),
          _SecondaryButton(
            label: 'SCAN QR CODE',
            icon: Icons.qr_code_scanner,
            onPressed: () => setState(() => _isScanning = true),
          ),
          const SizedBox(height: 24),
          const Center(
            child: Text('or', style: TextStyle(color: AppTheme.textDim)),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _codeController,
            textCapitalization: TextCapitalization.characters,
            style:
                const TextStyle(color: Colors.white, fontFamily: 'monospace'),
            decoration: const InputDecoration(hintText: 'Enter session code'),
          ),
          const SizedBox(height: 12),
          _PrimaryButton(
            label: _isBusy ? 'CONNECTING...' : 'CONNECT',
            icon: Icons.link,
            onPressed:
                _isBusy ? null : () => _joinSession(_codeController.text),
          ),
          const SizedBox(height: 18),
          const _InfoCard(
            text:
                'You must be on the same WiFi as the host, or connected to the host phone hotspot.',
          ),
          if (webrtc.state == AppConnectionState.error) ...[
            const SizedBox(height: 12),
            Text(webrtc.errorMessage,
                style: const TextStyle(color: AppTheme.red)),
          ],
        ],
      ),
    );
  }

  Widget _buildGuestActive(WebRTCService webrtc) {
    final controller = _guestController ?? webrtc.guestController;
    final isBrowserAudio =
        webrtc.hasRemoteAudio && controller?.isLoaded != true;
    return _Page(
      title: 'CONNECTED TO HOST',
      onBack: _leaveSession,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatusPill(
            icon: controller?.isLoaded == true || isBrowserAudio
                ? Icons.check_circle
                : Icons.hourglass_top,
            text: isBrowserAudio
                ? 'Browser audio connected'
                : controller?.isLoaded == true
                    ? 'Receiving phone stream'
                    : 'Waiting for stream...',
          ),
          const SizedBox(height: 24),
          if (controller != null && controller.isLoaded)
            _GuestPlayerPanel(controller: controller)
          else
            const _InfoCard(
              text:
                  'Browser extension audio is playing through the WebRTC connection. Playback is controlled from the browser tab.',
            ),
          const SizedBox(height: 18),
          _VolumeSlider(
            value: _volume,
            onChanged: (value) {
              setState(() => _volume = value);
              webrtc.setVolume(value);
            },
          ),
          const SizedBox(height: 16),
          const _StatusPill(icon: Icons.sync, text: 'Sync: In Sync'),
          const Spacer(),
          _SecondaryButton(
            label: 'LEAVE SESSION',
            icon: Icons.exit_to_app,
            danger: true,
            onPressed: _leaveSession,
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
          MobileScanner(onDetect: _handleQrCode),
          SafeArea(
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => setState(() => _isScanning = false),
                    ),
                    const Expanded(
                      child: Text(
                        'Scan QR Code',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HostPlayerPanel extends StatefulWidget {
  const _HostPlayerPanel({
    required this.controller,
    required this.onSeek,
    this.onFullscreen,
  });

  final HostSessionController controller;
  final ValueChanged<int> onSeek;
  final VoidCallback? onFullscreen;

  @override
  State<_HostPlayerPanel> createState() => _HostPlayerPanelState();
}

class _HostPlayerPanelState extends State<_HostPlayerPanel> {
  @override
  void initState() {
    super.initState();
    // Listen to VideoPlayerController changes so the widget rebuilds
    // when initialization completes and when play/pause state changes.
    widget.controller.videoController?.addListener(_onVideoChange);
  }

  @override
  void didUpdateWidget(_HostPlayerPanel old) {
    super.didUpdateWidget(old);
    if (old.controller.videoController != widget.controller.videoController) {
      old.controller.videoController?.removeListener(_onVideoChange);
      widget.controller.videoController?.addListener(_onVideoChange);
    }
  }

  @override
  void dispose() {
    widget.controller.videoController?.removeListener(_onVideoChange);
    super.dispose();
  }

  void _onVideoChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final videoController = widget.controller.videoController;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.controller.isVideoPlayback &&
            videoController != null &&
            videoController.value.isInitialized) ...[
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AspectRatio(
                  aspectRatio: videoController.value.aspectRatio,
                  child: VideoPlayer(videoController),
                ),
              ),
              if (widget.onFullscreen != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: IconButton(
                    onPressed: widget.onFullscreen,
                    icon: const Icon(Icons.fullscreen, color: Colors.white),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black54,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
        ],
        _TimelinePanel(
          title: widget.controller.file?.name ?? 'Selected media',
          positionStream: widget.controller.positionStream,
          position: widget.controller.position,
          duration: widget.controller.duration,
          readOnly: false,
          onSeek: widget.onSeek,
        ),
      ],
    );
  }
}

class _GuestPlayerPanel extends StatelessWidget {
  const _GuestPlayerPanel({required this.controller});

  final GuestSessionController controller;

  @override
  Widget build(BuildContext context) {
    return _TimelinePanel(
      title: controller.streamUrl ?? 'Receiving stream...',
      positionStream: controller.positionStream,
      position: controller.position,
      duration: controller.duration,
      readOnly: true,
    );
  }
}

class _DiscoveredSessions extends StatelessWidget {
  const _DiscoveredSessions({
    required this.sessions,
    required this.isLoading,
    required this.onRefresh,
    required this.onJoin,
  });

  final List<DiscoveredSession> sessions;
  final bool isLoading;
  final VoidCallback onRefresh;
  final ValueChanged<DiscoveredSession> onJoin;

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.card,
          border: Border.all(color: AppTheme.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              isLoading ? Icons.search : Icons.devices,
              color: AppTheme.accent,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isLoading
                    ? 'Looking for nearby hosts...'
                    : 'No nearby hosts found',
                style: const TextStyle(color: AppTheme.textDim),
              ),
            ),
            IconButton(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh, color: AppTheme.accent),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Nearby hosts',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        ...sessions.map(
          (session) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: () => onJoin(session),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.card,
                  border: Border.all(color: AppTheme.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      session.isMobileSource
                          ? Icons.smartphone
                          : Icons.computer,
                      color: AppTheme.accent,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            session.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            session.sessionId,
                            style: const TextStyle(
                              color: AppTheme.textDim,
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: AppTheme.textDim),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TimelinePanel extends StatelessWidget {
  const _TimelinePanel({
    required this.title,
    required this.positionStream,
    required this.position,
    required this.duration,
    required this.readOnly,
    this.onSeek,
  });

  final String title;
  final Stream<Duration> positionStream;
  final Duration position;
  final Duration? duration;
  final bool readOnly;
  final ValueChanged<int>? onSeek;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: positionStream,
      initialData: position,
      builder: (context, snapshot) {
        final pos = snapshot.data ?? Duration.zero;
        final total = duration ?? Duration.zero;
        final maxMs =
            total.inMilliseconds <= 0 ? 1.0 : total.inMilliseconds.toDouble();
        final value = pos.inMilliseconds.clamp(0, maxMs.toInt()).toDouble();
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.music_note, color: AppTheme.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              Slider(
                value: value,
                max: maxMs,
                activeColor: AppTheme.accent,
                inactiveColor: Colors.white12,
                onChanged:
                    readOnly ? null : (next) => onSeek?.call(next.round()),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_fmt(pos),
                      style: const TextStyle(color: AppTheme.textDim)),
                  Text(_fmt(total),
                      style: const TextStyle(color: AppTheme.textDim)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String _fmt(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.child, this.title, this.onBack});

  final Widget child;
  final String? title;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: ValueKey(title ?? 'welcome'),
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Row(
              children: [
                IconButton(
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                ),
                Expanded(
                  child: Text(
                    title!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight),
                    child: IntrinsicHeight(child: child),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaybackModePicker extends StatelessWidget {
  const _PlaybackModePicker({required this.value, required this.onChanged});

  final HostPlaybackMode value;
  final ValueChanged<HostPlaybackMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.card,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ModeSegment(
              label: 'Audio only',
              icon: Icons.volume_up,
              selected: value == HostPlaybackMode.audioOnly,
              onPressed: () => onChanged(HostPlaybackMode.audioOnly),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _ModeSegment(
              label: 'Video + audio',
              icon: Icons.movie,
              selected: value == HostPlaybackMode.videoWithAudio,
              onPressed: () => onChanged(HostPlaybackMode.videoWithAudio),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeSegment extends StatelessWidget {
  const _ModeSegment({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      style: TextButton.styleFrom(
        backgroundColor: selected ? AppTheme.accent : Colors.transparent,
        foregroundColor: selected ? Colors.white : AppTheme.textDim,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    );
  }
}

class _FileCard extends StatelessWidget {
  const _FileCard({required this.file});

  final PlatformFile? file;

  @override
  Widget build(BuildContext context) {
    final size = file == null ? '' : ' (${_formatSize(file!.size)})';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            file == null
                ? Icons.insert_drive_file_outlined
                : Icons.check_circle,
            color: file == null ? AppTheme.textDim : AppTheme.green,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              file == null ? 'No file selected' : '${file!.name}$size',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
}

class _QrPanel extends StatelessWidget {
  const _QrPanel({required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context) {
    final url = 'https://synchronization-807q.onrender.com/c/$sessionId';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          QrImageView(data: url, size: 160, backgroundColor: Colors.white),
          const SizedBox(height: 12),
          Text(
            sessionId,
            style: const TextStyle(
              color: AppTheme.accent,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w900,
              fontSize: 22,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }
}

class _VolumeSlider extends StatelessWidget {
  const _VolumeSlider({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.volume_down, color: AppTheme.textDim),
        Expanded(
          child: Slider(
            value: value,
            activeColor: AppTheme.accent,
            inactiveColor: Colors.white12,
            onChanged: onChanged,
          ),
        ),
        const Icon(Icons.volume_up, color: AppTheme.textDim),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: AppTheme.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: AppTheme.textDim, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppTheme.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppTheme.accent,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.accent,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppTheme.surface,
        disabledForegroundColor: AppTheme.textDim,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.danger = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppTheme.red : AppTheme.accent;
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        minimumSize: const Size(double.infinity, 56),
        side: BorderSide(color: color.withValues(alpha: 0.55)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.onPressed,
    this.large = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final size = large ? 66.0 : 50.0;
    return SizedBox(
      width: size,
      height: size,
      child: IconButton.filled(
        onPressed: onPressed,
        icon: Icon(icon, size: large ? 34 : 24),
        style: IconButton.styleFrom(
          backgroundColor: large ? AppTheme.accent : AppTheme.surface,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppTheme.surface.withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Fullscreen video overlay — immersive movie-watching experience
// ─────────────────────────────────────────────────────────────────────────────

class _FullscreenVideoOverlay extends StatefulWidget {
  const _FullscreenVideoOverlay({
    required this.controller,
    required this.onExit,
  });

  final HostSessionController controller;
  final VoidCallback onExit;

  @override
  State<_FullscreenVideoOverlay> createState() =>
      _FullscreenVideoOverlayState();
}

class _FullscreenVideoOverlayState extends State<_FullscreenVideoOverlay> {
  bool _showControls = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    widget.controller.videoController?.addListener(_onVideoTick);
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    widget.controller.videoController?.removeListener(_onVideoTick);
    super.dispose();
  }

  void _onVideoTick() {
    if (mounted) setState(() {});
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _scheduleHide();
  }

  String _fmt(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final vc = widget.controller.videoController;
    if (vc == null || !vc.value.isInitialized) {
      return const SizedBox.expand(
        child: ColoredBox(color: Colors.black),
      );
    }

    final position = vc.value.position;
    final duration = vc.value.duration;
    final maxMs =
        duration.inMilliseconds <= 0 ? 1.0 : duration.inMilliseconds.toDouble();
    final posMs = position.inMilliseconds.clamp(0, maxMs.toInt()).toDouble();

    return GestureDetector(
      onTap: _toggleControls,
      child: Container(
        color: Colors.black,
        child: Stack(
          children: [
            // ── Video ─────────────────────────────────────────────────────
            Center(
              child: AspectRatio(
                aspectRatio: vc.value.aspectRatio,
                child: VideoPlayer(vc),
              ),
            ),

            // ── Controls overlay ──────────────────────────────────────────
            if (_showControls)
              Container(
                color: Colors.black38,
                child: SafeArea(
                  child: Column(
                    children: [
                      // Top bar: exit fullscreen
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        child: Row(
                          children: [
                            IconButton(
                              onPressed: widget.onExit,
                              icon: const Icon(Icons.fullscreen_exit,
                                  color: Colors.white, size: 28),
                            ),
                            Expanded(
                              child: Text(
                                widget.controller.file?.name ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Center: play/pause + skip
                      const Spacer(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            onPressed: () => widget.controller.seekTo(
                              (position.inMilliseconds - 10000)
                                  .clamp(0, 1 << 31),
                            ),
                            icon: const Icon(Icons.replay_10,
                                color: Colors.white, size: 36),
                          ),
                          const SizedBox(width: 32),
                          IconButton(
                            onPressed: () {
                              vc.value.isPlaying
                                  ? widget.controller.pause()
                                  : widget.controller.play();
                            },
                            icon: Icon(
                              vc.value.isPlaying
                                  ? Icons.pause_circle_filled
                                  : Icons.play_circle_filled,
                              color: Colors.white,
                              size: 56,
                            ),
                          ),
                          const SizedBox(width: 32),
                          IconButton(
                            onPressed: () => widget.controller.seekTo(
                              position.inMilliseconds + 10000,
                            ),
                            icon: const Icon(Icons.forward_10,
                                color: Colors.white, size: 36),
                          ),
                        ],
                      ),
                      const Spacer(),

                      // Bottom: seek bar + times
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Row(
                          children: [
                            Text(_fmt(position),
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12)),
                            Expanded(
                              child: Slider(
                                value: posMs,
                                max: maxMs,
                                activeColor: AppTheme.accent,
                                inactiveColor: Colors.white24,
                                onChanged: (val) {
                                  widget.controller.seekTo(val.round());
                                  _scheduleHide();
                                },
                              ),
                            ),
                            Text(_fmt(duration),
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
