import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

const String _ntfyHost = 'ntfy.sh';
String _topic(String ch) => 'vibelink_$ch';

// ──────────────────────────────────────────────
// Enum: 3 transport types in one APK
// ──────────────────────────────────────────────
enum RelayType { websocket, httpStream, httpPoll }

extension RelayTypeMeta on RelayType {
  String get label {
    switch (this) {
      case RelayType.websocket:  return '⚡ WebSocket (WSS 443)';
      case RelayType.httpStream: return '🌊 HTTP Stream (SSE 443)';
      case RelayType.httpPoll:   return '🔄 HTTP Polling (HTTPS 443)';
    }
  }
  String get shortLabel {
    switch (this) {
      case RelayType.websocket:  return 'WebSocket';
      case RelayType.httpStream: return 'HTTP Stream';
      case RelayType.httpPoll:   return 'HTTP Polling';
    }
  }
  String get description {
    switch (this) {
      case RelayType.websocket:  return 'Eng tez (~15ms). Real-vaqt WebSocket ulanishi.';
      case RelayType.httpStream: return 'O\'rtacha (~25ms). HTTP oqimi (SSE). Barqaror.';
      case RelayType.httpPoll:   return 'Eng ishonchli (~300ms). Oddiy HTTP so\'rovlar. Har joyda ishlaydi.';
    }
  }
  String get key {
    switch (this) {
      case RelayType.websocket:  return 'websocket';
      case RelayType.httpStream: return 'httpStream';
      case RelayType.httpPoll:   return 'httpPoll';
    }
  }
  static RelayType fromKey(String key) {
    switch (key) {
      case 'httpStream': return RelayType.httpStream;
      case 'httpPoll':   return RelayType.httpPoll;
      default:           return RelayType.websocket;
    }
  }
}

// ──────────────────────────────────────────────
// Abstract backend interface
// ──────────────────────────────────────────────
abstract class RelayBackend {
  void Function(Map<String, dynamic> data)? onMessage;
  void Function()? onConnected;
  void Function()? onDisconnected;

  bool get isConnected;
  String get channel;

  Future<void> connect(String ch);
  void disconnect();
  Future<void> publish(Map<String, dynamic> data);
}

// ──────────────────────────────────────────────
// Backend 1: WebSocket (WSS Port 443)
//  — Fastest, real-time, persistent connection
// ──────────────────────────────────────────────
class WsBackend extends RelayBackend {
  WebSocketChannel? _ws;
  StreamSubscription? _sub;
  String _ch = '';
  bool _connected = false;

  @override bool get isConnected => _connected;
  @override String get channel => _ch;

  @override
  Future<void> connect(String ch) async {
    disconnect();
    _ch = ch;
    try {
      _ws = WebSocketChannel.connect(
        Uri.parse('wss://$_ntfyHost/${_topic(ch)}/ws'),
      );
      // Wait for the websocket to be ready
      await _ws!.ready.timeout(const Duration(seconds: 8));
      _connected = true;
      onConnected?.call();
      _sub = _ws!.stream.listen(
        (raw) => _parse(raw.toString()),
        onError: (e) {
          debugPrint('[WS] error: $e');
          _connected = false;
          onDisconnected?.call();
        },
        onDone: () {
          debugPrint('[WS] closed');
          _connected = false;
          onDisconnected?.call();
        },
      );
    } catch (e) {
      debugPrint('[WS] connect fail: $e');
      _connected = false;
      onDisconnected?.call();
    }
  }

  void _parse(String raw) {
    try {
      final env = jsonDecode(raw) as Map<String, dynamic>;
      if (env['event'] == 'message') {
        final body = env['message'] as String? ?? '';
        if (body.isNotEmpty) {
          final data = jsonDecode(body) as Map<String, dynamic>;
          onMessage?.call(data);
        }
      } else if (env['event'] == 'open') {
        _connected = true;
        onConnected?.call();
      }
    } catch (e) {
      debugPrint('[WS] parse: $e');
    }
  }

  @override
  Future<void> publish(Map<String, dynamic> data) async {
    if (_ch.isEmpty) return;
    try {
      http.post(
        Uri.parse('https://$_ntfyHost/${_topic(_ch)}'),
        body: jsonEncode(data),
      );
    } catch (e) {
      debugPrint('[WS] pub: $e');
    }
  }

  @override
  void disconnect() {
    _sub?.cancel();
    _sub = null;
    _ws?.sink.close();
    _ws = null;
    _connected = false;
  }
}

// ──────────────────────────────────────────────
// Backend 2: HTTP Stream / SSE (Port 443)
//  — Server-sent events, no WebSocket needed
// ──────────────────────────────────────────────
class HttpStreamBackend extends RelayBackend {
  http.Client? _client;
  StreamSubscription? _sub;
  String _ch = '';
  bool _connected = false;

  @override bool get isConnected => _connected;
  @override String get channel => _ch;

  @override
  Future<void> connect(String ch) async {
    disconnect();
    _ch = ch;
    _client = http.Client();
    try {
      final req = http.Request(
        'GET',
        Uri.parse('https://$_ntfyHost/${_topic(ch)}/json'),
      );
      req.headers['Accept'] = 'application/x-ndjson';
      final resp = await _client!.send(req).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        _connected = true;
        onConnected?.call();
        _sub = resp.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
              (line) {
                if (line.trim().isEmpty) return;
                try {
                  final env = jsonDecode(line) as Map<String, dynamic>;
                  if (env['event'] == 'message') {
                    final body = env['message'] as String? ?? '';
                    if (body.isNotEmpty) {
                      final data = jsonDecode(body) as Map<String, dynamic>;
                      onMessage?.call(data);
                    }
                  } else if (env['event'] == 'open') {
                    _connected = true;
                    onConnected?.call();
                  }
                } catch (_) {}
              },
              onError: (e) {
                debugPrint('[STREAM] err: $e');
                _connected = false;
                onDisconnected?.call();
              },
              onDone: () {
                debugPrint('[STREAM] done');
                _connected = false;
                onDisconnected?.call();
              },
            );
      } else {
        _connected = false;
        onDisconnected?.call();
      }
    } catch (e) {
      debugPrint('[STREAM] connect fail: $e');
      _connected = false;
      onDisconnected?.call();
    }
  }

  @override
  Future<void> publish(Map<String, dynamic> data) async {
    if (_ch.isEmpty) return;
    try {
      http.post(
        Uri.parse('https://$_ntfyHost/${_topic(_ch)}'),
        body: jsonEncode(data),
      );
    } catch (e) {
      debugPrint('[STREAM] pub: $e');
    }
  }

  @override
  void disconnect() {
    _sub?.cancel();
    _sub = null;
    _client?.close();
    _client = null;
    _connected = false;
  }
}

// ──────────────────────────────────────────────
// Backend 3: HTTP Polling (Port 443)
//  — Most reliable, works everywhere, no
//    persistent connection needed at all
// ──────────────────────────────────────────────
class HttpPollBackend extends RelayBackend {
  Timer? _pollTimer;
  String _ch = '';
  bool _connected = false;
  String _sinceId = '';
  bool _polling = false;

  @override bool get isConnected => _connected;
  @override String get channel => _ch;

  @override
  Future<void> connect(String ch) async {
    disconnect();
    _ch = ch;
    _sinceId = '';
    _polling = false;

    // Test connectivity first
    try {
      final res = await http.get(
        Uri.parse('https://$_ntfyHost/${_topic(ch)}/json?poll=1&since=1s'),
      ).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        // Mark any existing IDs as seen so we don't replay
        _extractLastId(res.body);
        _connected = true;
        onConnected?.call();
        _startPoll();
      } else {
        _connected = false;
        onDisconnected?.call();
      }
    } catch (e) {
      debugPrint('[POLL] connect fail: $e');
      _connected = false;
      onDisconnected?.call();
    }
  }

  void _extractLastId(String body) {
    final lines = body.trim().split('\n');
    for (final line in lines.reversed) {
      if (line.trim().isEmpty) continue;
      try {
        final env = jsonDecode(line) as Map<String, dynamic>;
        final id = env['id'] as String?;
        if (id != null && id.isNotEmpty) {
          _sinceId = id;
          return;
        }
      } catch (_) {}
    }
  }

  void _startPoll() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 300), (_) => _doPoll());
  }

  Future<void> _doPoll() async {
    if (_ch.isEmpty || _polling) return;
    _polling = true;
    try {
      final since = _sinceId.isNotEmpty ? _sinceId : '3s';
      final res = await http.get(
        Uri.parse('https://$_ntfyHost/${_topic(_ch)}/json?poll=1&since=$since'),
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200 && res.body.trim().isNotEmpty) {
        final lines = res.body.trim().split('\n');
        for (final line in lines) {
          if (line.trim().isEmpty) continue;
          try {
            final env = jsonDecode(line) as Map<String, dynamic>;
            final id = env['id'] as String?;
            if (id != null && id.isNotEmpty) _sinceId = id;
            if (env['event'] != 'message') continue;
            final body = env['message'] as String? ?? '';
            if (body.isNotEmpty) {
              final data = jsonDecode(body) as Map<String, dynamic>;
              onMessage?.call(data);
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      // Silently retry on next poll
    }
    _polling = false;
  }

  @override
  Future<void> publish(Map<String, dynamic> data) async {
    if (_ch.isEmpty) return;
    try {
      http.post(
        Uri.parse('https://$_ntfyHost/${_topic(_ch)}'),
        body: jsonEncode(data),
      );
    } catch (e) {
      debugPrint('[POLL] pub: $e');
    }
  }

  @override
  void disconnect() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _connected = false;
    _polling = false;
  }
}

// ──────────────────────────────────────────────
// Factory
// ──────────────────────────────────────────────
RelayBackend createBackend(RelayType type) {
  switch (type) {
    case RelayType.websocket:  return WsBackend();
    case RelayType.httpStream: return HttpStreamBackend();
    case RelayType.httpPoll:   return HttpPollBackend();
  }
}
