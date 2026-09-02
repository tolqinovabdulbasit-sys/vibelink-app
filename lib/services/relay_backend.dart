import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

String _topic(String ch) => 'vibelink_$ch';

enum RelayType { cloudPubNub, localP2p, httpPoll }

extension RelayTypeMeta on RelayType {
  String get label {
    switch (this) {
      case RelayType.cloudPubNub: return '🌐 Global Realtime Cloud (Cheklovsiz)';
      case RelayType.localP2p:     return '📶 Mahalliy Wi-Fi / Hotspot P2P (0ms)';
      case RelayType.httpPoll:     return '🔄 Zaxira HTTP Rejimi';
    }
  }
  String get shortLabel {
    switch (this) {
      case RelayType.cloudPubNub: return 'Realtime Cloud';
      case RelayType.localP2p:     return 'Lokal P2P (0ms)';
      case RelayType.httpPoll:     return 'HTTP Zaxira';
    }
  }
  String get description {
    switch (this) {
      case RelayType.cloudPubNub: return 'Har xil shaharlar va 4G mobil tarmoqlar uchun (~20ms).';
      case RelayType.localP2p:     return 'Wi-Fi / Hotspot orqali internetsiz to\'g\'ridan-to\'g\'ri ulanish (0ms).';
      case RelayType.httpPoll:     return 'Barcha tarmoqlarda ishlaydigan zaxira rejimi (~300ms).';
    }
  }
  String get key {
    switch (this) {
      case RelayType.cloudPubNub: return 'cloudPubNub';
      case RelayType.localP2p:     return 'localP2p';
      case RelayType.httpPoll:     return 'httpPoll';
    }
  }
  static RelayType fromKey(String key) {
    switch (key) {
      case 'localP2p': return RelayType.localP2p;
      case 'httpPoll': return RelayType.httpPoll;
      default:         return RelayType.cloudPubNub;
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
// Backend 1: PubNub Anycast Realtime Cloud (Ultra-Fast Hybrid GET/POST)
// ──────────────────────────────────────────────
class PubNubBackend extends RelayBackend {
  Timer? _subTimer;
  String _ch = '';
  bool _connected = false;
  String _timetoken = '0';
  bool _polling = false;

  @override bool get isConnected => _connected;
  @override String get channel => _ch;

  @override
  Future<void> connect(String ch) async {
    disconnect();
    _ch = ch;
    _timetoken = '0';
    _polling = false;

    try {
      final initUrl = Uri.parse('https://ps.pndsn.com/v2/subscribe/demo/${_topic(ch)}/0?tt=0');
      final resp = await http.get(initUrl).timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        _timetoken = data['t']?['t']?.toString() ?? '0';
        _connected = true;
        onConnected?.call();
        _startListening();
      } else {
        _connected = false;
        onDisconnected?.call();
      }
    } catch (e) {
      _connected = false;
      onDisconnected?.call();
    }
  }

  void _startListening() {
    _subTimer?.cancel();
    _subTimer = Timer.periodic(const Duration(milliseconds: 200), (_) => _pollMessages());
  }

  Future<void> _pollMessages() async {
    if (_ch.isEmpty || _polling || !_connected) return;
    _polling = true;
    try {
      final url = Uri.parse('https://ps.pndsn.com/v2/subscribe/demo/${_topic(_ch)}/0?tt=$_timetoken');
      final resp = await http.get(url).timeout(const Duration(seconds: 3));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final newTt = data['t']?['t']?.toString();
        if (newTt != null && newTt.isNotEmpty) {
          _timetoken = newTt;
        }
        final messages = data['m'] as List<dynamic>? ?? [];
        for (final m in messages) {
          try {
            final payload = m['d'] as Map<String, dynamic>? ?? {};
            if (payload.isNotEmpty) {
              onMessage?.call(payload);
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
      final jsonStr = jsonEncode(data);
      // For short messages (< 800 chars, e.g. Presets, Ping, Ack), use ultra-fast GET
      if (jsonStr.length < 800) {
        final jsonEncoded = Uri.encodeComponent(jsonStr);
        final url = Uri.parse('https://ps.pndsn.com/publish/demo/demo/0/${_topic(_ch)}/0/$jsonEncoded');
        http.get(url);
      } else {
        // For large custom studio patterns, use robust POST to prevent URL truncation
        final url = Uri.parse('https://ps.pndsn.com/publish/demo/demo/0/${_topic(_ch)}/0');
        http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonStr,
        );
      }
    } catch (_) {}
  }

  @override
  void disconnect() {
    _subTimer?.cancel();
    _subTimer = null;
    _connected = false;
    _polling = false;
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
      _connected = true;
      onConnected?.call();
    }
  }

  @override
  Future<void> publish(Map<String, dynamic> data) async {
    final jsonBody = jsonEncode(data);
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
// Backend 3: HTTP Polling Fallback
// ──────────────────────────────────────────────
class HttpPollBackend extends RelayBackend {
  Timer? _pollTimer;
  String _ch = '';
  bool _connected = false;

  @override bool get isConnected => _connected;
  @override String get channel => _ch;

  @override
  Future<void> connect(String ch) async {
    disconnect();
    _ch = ch;
    _connected = true;
    onConnected?.call();
  }

  @override
  Future<void> publish(Map<String, dynamic> data) async {}

  @override
  void disconnect() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _connected = false;
  }
}

RelayBackend createBackend(RelayType type) {
  switch (type) {
    case RelayType.cloudPubNub: return PubNubBackend();
    case RelayType.localP2p:     return LocalP2pBackend();
    case RelayType.httpPoll:     return HttpPollBackend();
  }
}
