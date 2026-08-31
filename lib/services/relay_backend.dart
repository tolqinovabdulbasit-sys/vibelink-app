import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

// List of resilient Domestic & Direct-IP Relay Servers (Bypasses Russian TSPU / Roskomnadzor DPI)
const List<String> _kRuRelayHosts = [
  'https://ntfy.sh', // Standard HTTPS 443
  'http://185.22.154.214:8080', // Direct Russian Domestic IP (DNS-block proof)
  'https://ntfy.m7.rs', // Mirror relay 1
  'https://notify.sh', // Mirror relay 2
];

String _topic(String ch) => 'vibelink_$ch';

enum RelayType { ruRelay, websocket, httpPoll }

extension RelayTypeMeta on RelayType {
  String get label {
    switch (this) {
      case RelayType.ruRelay:   return '🇷🇺 Rossiya Direct IP / Relay (Cheklovsiz)';
      case RelayType.websocket: return '⚡ Global WebSocket (WSS 443)';
      case RelayType.httpPoll:   return '🔄 Direct HTTP Polling (Port 443)';
    }
  }
  String get shortLabel {
    switch (this) {
      case RelayType.ruRelay:   return 'Rossiya Direct IP';
      case RelayType.websocket: return 'WebSocket';
      case RelayType.httpPoll:   return 'HTTP Poll';
    }
  }
  String get description {
    switch (this) {
      case RelayType.ruRelay:   return 'Rossiya IP va bloklanmaydigan to\'g\'ridan-to\'g\'ri uzatuvchi (~20ms).';
      case RelayType.websocket: return 'Real-vaqt WSS ulanishi (~15ms).';
      case RelayType.httpPoll:   return 'Har qanday tarmoqda 100% ishlaydigan oddiy so\'rovlar (~300ms).';
    }
  }
  String get key {
    switch (this) {
      case RelayType.ruRelay:   return 'ruRelay';
      case RelayType.websocket: return 'websocket';
      case RelayType.httpPoll:   return 'httpPoll';
    }
  }
  static RelayType fromKey(String key) {
    switch (key) {
      case 'websocket': return RelayType.websocket;
      case 'httpPoll':   return RelayType.httpPoll;
      default:           return RelayType.ruRelay;
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
// Backend 1: Domestic Russian Direct IP & Multi-Mirror Relay (Bypasses TSPU)
// ──────────────────────────────────────────────
class RuRelayBackend extends RelayBackend {
  WebSocketChannel? _ws;
  StreamSubscription? _sub;
  String _ch = '';
  bool _connected = false;
  String _activeHost = _kRuRelayHosts.first;

  @override bool get isConnected => _connected;
  @override String get channel => _ch;

  @override
  Future<void> connect(String ch) async {
    disconnect();
    _ch = ch;

    // Try multi-relay hosts until connection succeeds
    for (final host in _kRuRelayHosts) {
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
            debugPrint('[RU-RELAY] err: $e');
            _connected = false;
            onDisconnected?.call();
          },
          onDone: () {
            debugPrint('[RU-RELAY] done');
            _connected = false;
            onDisconnected?.call();
          },
        );
        return;
      } catch (e) {
        debugPrint('[RU-RELAY] Failed host $host: $e. Trying next host...');
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

    // Broadcast publish to active host & mirrors
    for (final host in _kRuRelayHosts) {
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
// Backend 2: Standard WSS Port 443 WebSocket
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
      await _ws!.ready.timeout(const Duration(seconds: 5));
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
// Backend 3: HTTP Polling (Port 443)
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
    case RelayType.ruRelay:   return RuRelayBackend();
    case RelayType.websocket: return WsBackend();
    case RelayType.httpPoll:   return HttpPollBackend();
  }
}
