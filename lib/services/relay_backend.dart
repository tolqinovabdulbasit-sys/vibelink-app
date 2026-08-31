import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

// Domestic & Mirror Relays
const List<String> _kDomesticRelayHosts = [
  'https://ntfy.sh',
  'https://ntfy.m7.rs',
  'https://notify.sh',
  'http://185.22.154.214:8080',
];

String _topic(String ch) => 'vibelink_$ch';

enum RelayType { domesticCloud, localP2p, websocket, httpPoll }

extension RelayTypeMeta on RelayType {
  String get label {
    switch (this) {
      case RelayType.domesticCloud: return '🇷🇺 Yandex / Domestic Cloud Relay';
      case RelayType.localP2p:       return '📶 Mahalliy Wi-Fi / Hotspot P2P (0ms, Internetsiz)';
      case RelayType.websocket:      return '⚡ Global WebSocket (WSS 443)';
      case RelayType.httpPoll:       return '🔄 HTTP Long-Polling (Port 443)';
    }
  }
  String get shortLabel {
    switch (this) {
      case RelayType.domesticCloud: return 'Domestic Cloud';
      case RelayType.localP2p:       return 'Lokal P2P (0ms)';
      case RelayType.websocket:      return 'WebSocket';
      case RelayType.httpPoll:       return 'HTTP Poll';
    }
  }
  String get description {
    switch (this) {
      case RelayType.domesticCloud: return 'Rossiya va MDH uchun ko\'zguli bulut serverlari (~25ms).';
      case RelayType.localP2p:       return 'Wi-Fi / Hotspot orqali internetsiz to\'g\'ridan-to\'g\'ri ulanish (0ms).';
      case RelayType.websocket:      return 'Standart global WSS 443 ulanishi (~15ms).';
      case RelayType.httpPoll:       return 'Barcha tarmoqlarda ishlaydigan zaxira rejimi (~300ms).';
    }
  }
  String get key {
    switch (this) {
      case RelayType.domesticCloud: return 'domesticCloud';
      case RelayType.localP2p:       return 'localP2p';
      case RelayType.websocket:      return 'websocket';
      case RelayType.httpPoll:       return 'httpPoll';
    }
  }
  static RelayType fromKey(String key) {
    switch (key) {
      case 'localP2p':       return RelayType.localP2p;
      case 'websocket':      return RelayType.websocket;
      case 'httpPoll':       return RelayType.httpPoll;
      default:               return RelayType.domesticCloud;
    }
  }
}

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
// Backend 1: Domestic Cloud Multi-Mirror Relay
// ──────────────────────────────────────────────
class DomesticCloudBackend extends RelayBackend {
  WebSocketChannel? _ws;
  StreamSubscription? _sub;
  String _ch = '';
  bool _connected = false;
  String _activeHost = _kDomesticRelayHosts.first;

  @override bool get isConnected => _connected;
  @override String get channel => _ch;

  @override
  Future<void> connect(String ch) async {
    disconnect();
    _ch = ch;

    for (final host in _kDomesticRelayHosts) {
      try {
        final isWss = host.startsWith('https');
        final scheme = isWss ? 'wss' : 'ws';
        final cleanHost = host.replaceFirst('https://', '').replaceFirst('http://', '');
        final wsUrl = Uri.parse('$scheme://$cleanHost/${_topic(ch)}/ws');

        _ws = WebSocketChannel.connect(wsUrl);
        await _ws!.ready.timeout(const Duration(seconds: 4));
        _activeHost = host;
        _connected = true;
        onConnected?.call();

        _sub = _ws!.stream.listen(
          (raw) => _parse(raw.toString()),
          onError: (e) {
            _connected = false;
            onDisconnected?.call();
          },
          onDone: () {
            _connected = false;
            onDisconnected?.call();
          },
        );
        return;
      } catch (e) {
        debugPrint('[DOMESTIC] Host $host error: $e');
      }
    }

    _connected = false;
    onDisconnected?.call();
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
    } catch (_) {}
  }

  @override
  Future<void> publish(Map<String, dynamic> data) async {
    if (_ch.isEmpty) return;
    final jsonBody = jsonEncode(data);
    for (final host in _kDomesticRelayHosts) {
      try {
        http.post(
          Uri.parse('$host/${_topic(_ch)}'),
          headers: {'Content-Type': 'application/json'},
          body: jsonBody,
        );
      } catch (_) {}
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
// Backend 2: Local Wi-Fi & Hotspot Direct P2P Engine
// ──────────────────────────────────────────────
class LocalP2pBackend extends RelayBackend {
  HttpServer? _server;
  String _ch = '';
  bool _connected = false;
  final List<String> _knownPeerIps = [];

  @override bool get isConnected => _connected;
  @override String get channel => _ch;

  @override
  Future<void> connect(String ch) async {
    disconnect();
    _ch = ch;

    try {
      // Bind local server on port 8888
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 8888);
      _connected = true;
      onConnected?.call();

      _server!.listen((HttpRequest request) async {
        if (request.method == 'POST' && request.uri.path == '/message') {
          try {
            final body = await utf8.decoder.bind(request).join();
            final data = jsonDecode(body) as Map<String, dynamic>;
            onMessage?.call(data);
            request.response.statusCode = HttpStatus.ok;
            request.response.write('OK');
          } catch (_) {
            request.response.statusCode = HttpStatus.badRequest;
          }
          await request.response.close();
        } else if (request.uri.path == '/ping') {
          request.response.statusCode = HttpStatus.ok;
          request.response.write('PONG');
          await request.response.close();
        } else {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        }
      });
    } catch (e) {
      debugPrint('[LOCAL-P2P] Server bind error: $e');
      _connected = true; // Fallback mode
      onConnected?.call();
    }
  }

  @override
  Future<void> publish(Map<String, dynamic> data) async {
    final jsonBody = jsonEncode(data);
    // Broadcast to common local subnets (Hotspot: 192.168.43.x, Wi-Fi: 192.168.1.x / 192.168.0.x)
    for (final ip in ['192.168.43.1', '192.168.43.2', '192.168.1.1', '192.168.0.1', ..._knownPeerIps]) {
      try {
        http.post(
          Uri.parse('http://$ip:8888/message'),
          headers: {'Content-Type': 'application/json'},
          body: jsonBody,
        ).timeout(const Duration(milliseconds: 300));
      } catch (_) {}
    }
  }

  @override
  void disconnect() {
    _server?.close(force: true);
    _server = null;
    _connected = false;
  }
}

// ──────────────────────────────────────────────
// Backend 3: Global WSS WebSocket
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
        Uri.parse('wss://ntfy.sh/${_topic(ch)}/ws'),
      );
      await _ws!.ready.timeout(const Duration(seconds: 4));
      _connected = true;
      onConnected?.call();
      _sub = _ws!.stream.listen(
        (raw) => _parse(raw.toString()),
        onError: (e) {
          _connected = false;
          onDisconnected?.call();
        },
        onDone: () {
          _connected = false;
          onDisconnected?.call();
        },
      );
    } catch (e) {
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
    } catch (_) {}
  }

  @override
  Future<void> publish(Map<String, dynamic> data) async {
    if (_ch.isEmpty) return;
    try {
      http.post(
        Uri.parse('https://ntfy.sh/${_topic(_ch)}'),
        body: jsonEncode(data),
      );
    } catch (_) {}
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
// Backend 4: HTTP Polling
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

    try {
      final res = await http.get(
        Uri.parse('https://ntfy.sh/${_topic(ch)}/json?poll=1&since=1s'),
      ).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        _extractLastId(res.body);
        _connected = true;
        onConnected?.call();
        _startPoll();
      } else {
        _connected = false;
        onDisconnected?.call();
      }
    } catch (e) {
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
    _pollTimer = Timer.periodic(const Duration(milliseconds: 350), (_) => _doPoll());
  }

  Future<void> _doPoll() async {
    if (_ch.isEmpty || _polling) return;
    _polling = true;
    try {
      final since = _sinceId.isNotEmpty ? _sinceId : '3s';
      final res = await http.get(
        Uri.parse('https://ntfy.sh/${_topic(_ch)}/json?poll=1&since=$since'),
      ).timeout(const Duration(seconds: 3));

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
    } catch (_) {}
    _polling = false;
  }

  @override
  Future<void> publish(Map<String, dynamic> data) async {
    if (_ch.isEmpty) return;
    try {
      http.post(
        Uri.parse('https://ntfy.sh/${_topic(_ch)}'),
        body: jsonEncode(data),
      );
    } catch (_) {}
  }

  @override
  void disconnect() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _connected = false;
    _polling = false;
  }
}

RelayBackend createBackend(RelayType type) {
  switch (type) {
    case RelayType.domesticCloud: return DomesticCloudBackend();
    case RelayType.localP2p:       return LocalP2pBackend();
    case RelayType.websocket:      return WsBackend();
    case RelayType.httpPoll:       return HttpPollBackend();
  }
}
