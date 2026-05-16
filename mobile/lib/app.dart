import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'screens/home_screen.dart';
import 'services/webrtc_service.dart';
import 'services/discovery_service.dart';
import 'services/deep_link_service.dart';
import 'services/guest_session_controller.dart';

class SynchronizationApp extends StatelessWidget {
  const SynchronizationApp({super.key, this.enableDiscovery = true});

  final bool enableDiscovery;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => WebRTCService()),
        ChangeNotifierProvider(create: (_) => DiscoveryService()),
      ],
      child: MaterialApp(
        title: 'Synchronization',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        home: _DeepLinkWrapper(enableDiscovery: enableDiscovery),
      ),
    );
  }
}

/// Wraps HomeScreen and initialises DeepLinkService so that scanning a QR
/// (or tapping a link) while the app is open or cold-starts it will
/// automatically trigger a connection.
class _DeepLinkWrapper extends StatefulWidget {
  const _DeepLinkWrapper({required this.enableDiscovery});

  final bool enableDiscovery;

  @override
  State<_DeepLinkWrapper> createState() => _DeepLinkWrapperState();
}

class _DeepLinkWrapperState extends State<_DeepLinkWrapper> {
  final DeepLinkService _deepLinkService = DeepLinkService();

  @override
  void initState() {
    super.initState();
    _deepLinkService.onDeepLink = (sessionId, serverUrl) {
      // Connect as soon as a deep link arrives, regardless of current state
      final webrtc = context.read<WebRTCService>();
      webrtc.initializeGuest(GuestSessionController());
      webrtc.connect(sessionId, serverUrl);
    };
    _deepLinkService.init();
  }

  @override
  void dispose() {
    _deepLinkService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      HomeScreen(enableDiscovery: widget.enableDiscovery);
}
