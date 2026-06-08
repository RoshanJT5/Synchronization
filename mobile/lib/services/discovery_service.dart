import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:synchronization/services/location_service.dart';

/// A session announced on the signaling server.
class DiscoveredSession {
  final String sessionId;
  final String label;
  final int announcedAt;

  /// 'computer' (Chrome extension) or 'mobile-host' (phone LAN stream).
  final String type;

  const DiscoveredSession({
    required this.sessionId,
    required this.label,
    required this.announcedAt,
    this.type = 'computer',
  });

  bool get isMobileSource => type == 'mobile-source' || type == 'mobile-host';

  @override
  bool operator ==(Object other) =>
      other is DiscoveredSession && other.sessionId == sessionId;

  @override
  int get hashCode => sessionId.hashCode;
}

/// Connects to the signaling server and listens for active session
/// announcements. Provides a live list split into computer sessions and
/// mobile-source sessions so the UI can render them in separate sections.
class DiscoveryService extends ChangeNotifier {
  static const String _signalingServer =
      'https://synchronization-807q.onrender.com';

  io.Socket? _socket;
  List<DiscoveredSession> _sessions = [];
  bool _isConnected = false;
  bool _isConnecting = false;

  /// All sessions (computers + mobile sources).
  List<DiscoveredSession> get sessions => List.unmodifiable(_sessions);

  /// Only Chrome extension / computer sessions.
  List<DiscoveredSession> get computerSessions =>
      _sessions.where((s) => !s.isMobileSource).toList();

  /// Only mobile-source sessions.
  List<DiscoveredSession> get mobileSessions =>
      _sessions.where((s) => s.isMobileSource).toList();

  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;

  Future<void> startDiscovery() async {
    if (_isConnecting || _isConnected) return;
    _isConnecting = true;
    notifyListeners();

    _socket = io.io(
      _signalingServer,
      io.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .disableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(9999999)
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(8000)
          .setTimeout(30000)
          .setExtraHeaders({'User-Agent': 'SyncronizationMobile/1.0'})
          .build(),
    );

    _socket!.onConnect((_) {
      debugPrint('[Discovery] Connected');
      _isConnected = true;
      _isConnecting = false;
      notifyListeners();
      _requestActiveSessions();
    });

    // Bug fix: also update _isConnected on reconnect so the UI reflects
    // the correct state, then re-fetch the proximity-filtered session list.
    _socket!.on('reconnect', (_) {
      debugPrint('[Discovery] Reconnected');
      _isConnected = true;
      _isConnecting = false;
      notifyListeners();
      _requestActiveSessions();
    });

    _socket!.onConnectError((error) {
      debugPrint('[Discovery] Connect error: $error');
      _isConnecting = false;
      notifyListeners();
    });

    _socket!.onDisconnect((_) {
      debugPrint('[Discovery] Disconnected');
      _isConnected = false;
      notifyListeners();
    });

    // Listen for the new server event that tells us to re-fetch instead of wiping the UI
    _socket!.on('refresh-sessions-needed', (_) {
      _requestActiveSessions();
    });

    _socket!.on('active-sessions-updated', (data) {
      try {
        Map<String, dynamic> payload;
        if (data is List && data.isNotEmpty) {
          payload = Map<String, dynamic>.from(data.first as Map);
        } else if (data is Map) {
          payload = Map<String, dynamic>.from(data);
        } else {
          return;
        }
        final rawList =
            (payload['sessions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        _sessions = rawList
            .map((s) => DiscoveredSession(
                  sessionId: s['sessionId'] as String,
                  label: s['label'] as String? ?? 'Unknown',
                  announcedAt: (s['announcedAt'] as num?)?.toInt() ?? 0,
                  type: s['type'] as String? ?? 'computer',
                ))
            .toList();
        notifyListeners();
      } catch (e) {
        debugPrint('[Discovery] Parse error: $e');
      }
    });

    _socket!.connect();
  }

  /// Emits 'get-active-sessions' with the phone's GPS coordinates so the
  /// server only returns sessions within 50 metres.
  Future<void> _requestActiveSessions() async {
    final pos = await LocationService.getPosition();
    if (pos == null) {
      debugPrint('[Discovery] No GPS position — skipping session request');
      return;
    }
    _socket?.emit('get-active-sessions', {
      'lat': pos.lat,
      'lng': pos.lng,
    });
  }

  void stopDiscovery() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _sessions = [];
    _isConnected = false;
    _isConnecting = false;
    notifyListeners();
  }

  @override
  void dispose() {
    stopDiscovery();
    super.dispose();
  }
}
