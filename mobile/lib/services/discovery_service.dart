import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

/// Represents a streaming session announced by a Chrome extension.
class DiscoveredSession {
  final String sessionId;
  final String label;
  final int announcedAt;

  const DiscoveredSession({
    required this.sessionId,
    required this.label,
    required this.announcedAt,
  });

  @override
  bool operator ==(Object other) =>
      other is DiscoveredSession && other.sessionId == sessionId;

  @override
  int get hashCode => sessionId.hashCode;
}

/// Connects to the signaling server and listens for active session
/// announcements from Chrome extensions. Provides a live list that
/// the UI can display so the user can tap-to-connect without scanning a QR.
class DiscoveryService extends ChangeNotifier {
  static const String _signalingServer =
      'https://synchronization-5865.onrender.com';

  io.Socket? _socket;
  List<DiscoveredSession> _sessions = [];
  bool _isConnected = false;
  bool _isConnecting = false;

  List<DiscoveredSession> get sessions => List.unmodifiable(_sessions);
  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;

  /// Start listening for active sessions on the signaling server.
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
          .setReconnectionAttempts(5)
          .setReconnectionDelay(2000)
          .setTimeout(10000)
          .build(),
    );

    _socket!.onConnect((_) {
      debugPrint('[Discovery] Connected to signaling server');
      _isConnected = true;
      _isConnecting = false;
      notifyListeners();
      // Request the current list immediately
      _socket!.emit('get-active-sessions');
    });

    _socket!.onConnectError((error) {
      debugPrint('[Discovery] Connection error: $error');
      _isConnecting = false;
      notifyListeners();
    });

    _socket!.onDisconnect((_) {
      debugPrint('[Discovery] Disconnected');
      _isConnected = false;
      notifyListeners();
    });

    _socket!.on('active-sessions-updated', (data) {
      debugPrint('[Discovery] Sessions updated: $data');
      final rawList = (data['sessions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      _sessions = rawList
          .map((s) => DiscoveredSession(
                sessionId: s['sessionId'] as String,
                label: s['label'] as String? ?? 'Computer',
                announcedAt: (s['announcedAt'] as num?)?.toInt() ?? 0,
              ))
          .toList();
      notifyListeners();
    });

    _socket!.connect();
  }

  /// Stop discovery and disconnect from the signaling server.
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
