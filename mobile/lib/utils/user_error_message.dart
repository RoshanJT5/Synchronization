class UserErrorMessage {
  static String from(Object error) {
    final raw = error.toString().replaceFirst('Exception: ', '').trim();
    final message = raw.toLowerCase();

    if (message.contains('no local network') ||
        message.contains('no address associated') ||
        message.contains('network is unreachable') ||
        message.contains('failed host lookup')) {
      return 'No WiFi connected.';
    }

    if (message.contains('could not reach signaling server') ||
        message.contains('connection timed out') ||
        message.contains('timeout') ||
        message.contains('socketexception') ||
        message.contains('connection refused')) {
      return 'No internet connection.';
    }

    if (message.contains('session code') ||
        message.contains('invalid session') ||
        message.contains('not found')) {
      return 'Invalid session code.';
    }

    if (message.contains('permission')) {
      return 'Permission needed to continue.';
    }

    if (message.contains('file path') ||
        message.contains('file not found') ||
        message.contains('selected file')) {
      return 'Could not open this file.';
    }

    if (message.contains('ports') || message.contains('address already in use')) {
      return 'Streaming port is busy.';
    }

    if (message.contains('host disconnected')) {
      return 'Host disconnected.';
    }

    if (raw.isEmpty) return 'Something went wrong.';
    return raw.length <= 80 ? raw : 'Something went wrong.';
  }
}
