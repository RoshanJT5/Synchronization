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
      ..get('/stream', _handleStream);

    final handler = const shelf.Pipeline()
        .addMiddleware(_corsMiddleware())
        .addHandler(router.call);

    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
    return 'http://$localIp:$port/stream';
  }

  Future<shelf.Response> _handleStream(shelf.Request request) async {
    final path = _filePath;
    if (path == null) return shelf.Response.notFound('No file selected');

    final file = File(path);
    if (!await file.exists()) return shelf.Response.notFound('File not found');

    final fileSize = await file.length();
    final rangeHeader = request.headers['range'];
    if (rangeHeader != null) {
      return _handleRangeRequest(file, fileSize, rangeHeader);
    }

    return shelf.Response.ok(
      file.openRead(),
      headers: {
        'Content-Type': _mimeType ?? 'application/octet-stream',
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
    String rangeHeader,
  ) {
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
        'Content-Type': _mimeType ?? 'application/octet-stream',
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

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  bool get isRunning => _server != null;
}
