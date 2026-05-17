import 'dart:io';

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

class StreamServer {
  static const int port = 8080;

  HttpServer? _server;
  String? _filePath;
  String? _mimeType;

  Future<String> start(String filePath, String localIp) async {
    await stop();
    _filePath = filePath;
    _mimeType = _getMimeType(filePath);

    final router = Router()
      ..get('/ping', (shelf.Request request) => shelf.Response.ok('pong'))
      ..get('/stream', _handleStream)
      ..get('/audio', _handleAudio); // audio-only endpoint for guest devices

    final handler = const shelf.Pipeline()
        .addMiddleware(_corsMiddleware())
        .addHandler(router.call);

    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
    return 'http://$localIp:$port/stream';
  }

  /// URL for guest audio-only playback (works for both MP3 and MP4 sources).
  String? get audioUrl {
    final server = _server;
    if (server == null || _filePath == null) return null;
    final host = server.address.address == '0.0.0.0'
        ? 'localhost'
        : server.address.address;
    return 'http://$host:$port/audio';
  }

  Future<shelf.Response> _handleStream(shelf.Request request) async {
    return _serveFile(request, _mimeType);
  }

  /// Serves the same file but always with an audio-compatible MIME type.
  /// For MP4/MKV/AVI sources, this tells ExoPlayer/just_audio to treat it
  /// as audio-only so guests never get a video track.
  Future<shelf.Response> _handleAudio(shelf.Request request) async {
    final audioMime = _getAudioMimeType(_filePath ?? '');
    return _serveFile(request, audioMime);
  }

  Future<shelf.Response> _serveFile(
    shelf.Request request,
    String? contentType,
  ) async {
    final path = _filePath;
    if (path == null) return shelf.Response.notFound('No file selected');

    final file = File(path);
    if (!await file.exists()) return shelf.Response.notFound('File not found');

    final fileSize = await file.length();
    final rangeHeader = request.headers['range'];
    if (rangeHeader != null) {
      return _handleRangeRequest(
        file,
        fileSize,
        rangeHeader,
        contentType: contentType,
      );
    }

    return shelf.Response.ok(
      file.openRead(),
      headers: {
        'Content-Type': contentType ?? 'application/octet-stream',
        'Content-Length': '$fileSize',
        'Accept-Ranges': 'bytes',
        'Cache-Control': 'no-cache',
        'Connection': 'keep-alive',
      },
    );
  }

  shelf.Response _handleRangeRequest(
    File file,
    int fileSize,
    String rangeHeader, {
    String? contentType,
  }) {
    final match = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(rangeHeader);
    if (match == null) return shelf.Response(416, body: 'Invalid range');

    final start = int.parse(match.group(1)!);
    final requestedEnd = match.group(2);
    final end = requestedEnd == null || requestedEnd.isEmpty
        ? fileSize - 1
        : int.parse(requestedEnd).clamp(start, fileSize - 1);
    final length = end - start + 1;

    return shelf.Response(
      206,
      body: file.openRead(start, end + 1),
      headers: {
        'Content-Type': contentType ?? _mimeType ?? 'application/octet-stream',
        'Content-Range': 'bytes $start-$end/$fileSize',
        'Content-Length': '$length',
        'Accept-Ranges': 'bytes',
        'Cache-Control': 'no-cache',
      },
    );
  }

  shelf.Middleware _corsMiddleware() {
    return (handler) {
      return (request) async {
        if (request.method == 'OPTIONS') {
          return shelf.Response.ok('', headers: _corsHeaders);
        }
        final response = await handler(request);
        return response.change(headers: _corsHeaders);
      };
    };
  }

  Map<String, String> get _corsHeaders => const {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, HEAD, OPTIONS',
        'Access-Control-Allow-Headers': 'Range, Content-Type',
      };

  String _getMimeType(String path) {
    final ext = path.split('.').last.toLowerCase();
    const types = {
      'mp3': 'audio/mpeg',
      'mp4': 'video/mp4',
      'wav': 'audio/wav',
      'aac': 'audio/aac',
      'flac': 'audio/flac',
      'm4a': 'audio/mp4',
      'ogg': 'audio/ogg',
      'mkv': 'video/x-matroska',
      'avi': 'video/x-msvideo',
      'mov': 'video/quicktime',
    };
    return types[ext] ?? 'application/octet-stream';
  }

  /// Returns an audio-compatible MIME type for any file.
  /// Video containers (mp4/mkv/etc.) are mapped to audio/mp4 so that
  /// ExoPlayer on guest devices treats them as audio-only streams.
  String _getAudioMimeType(String path) {
    final ext = path.split('.').last.toLowerCase();
    const videoToAudio = {
      'mp4': 'audio/mp4',
      'mkv': 'audio/mp4',
      'avi': 'audio/mp4',
      'mov': 'audio/mp4',
    };
    if (videoToAudio.containsKey(ext)) return videoToAudio[ext]!;
    return _getMimeType(path); // mp3/wav/aac etc. already audio
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  bool get isRunning => _server != null;
}
