import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/vibration_pattern.dart';

enum ConnectionStatus { disconnected, connecting, connected }

// Uses a free public PeerJS server via WebSocket signaling
// Message types: OFFER, ANSWER, CANDIDATE, VIBE, LIVE_START, LIVE_STOP, PING, PONG, ACK
class PeerService extends ChangeNotifier {
  WebSocketChannel? _channel;
  ConnectionStatus _status = ConnectionStatus.disconnected;
  String? _targetPeerId;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  bool _liveActive = false;

  ConnectionStatus get status => _status;
  bool get isConnected => _status == ConnectionStatus.connected;
  bool get liveActive => _liveActive;

  // Callbacks set by screens
  Function(VibrationPattern)? onVibeReceived;
  Function()? onLiveStart;
  Function()? onLiveStop;
  Function(String)? onAckReceived;
  Function(String)? onError;

  // Signaling server (free public relay, no Firebase)
  static const _signalingUrl = 'wss://peerjs.metered.live/peerjs?key=peerjs&id=';

  Future<void> connect(String myPeerId) async {
    if (_status == ConnectionStatus.connecting) return;
    _status = ConnectionStatus.connecting;
    notifyListeners();
    try {
      final uri = Uri.parse('$_signalingUrl$myPeerId&token=vibelink');
      _channel = WebSocketChannel.connect(uri);
      _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDisconnect,
      );
      _status = ConnectionStatus.connected;
      notifyListeners();
      _startPing();
    } catch (e) {
      _status = ConnectionStatus.disconnected;
      notifyListeners();
      onError?.call('Ulanish xatosi: $e');
    }
  }

  void _onMessage(dynamic raw) {
    try {
      final msg = jsonDecode(raw.toString());
      final type = msg['type'] as String? ?? '';
      switch (type) {
        case 'VIBE':
          final pattern = VibrationPattern.fromJson(msg['pattern']);
          onVibeReceived?.call(pattern);
          _sendAck(msg['id'] ?? '');
          break;
        case 'LIVE_START':
          _liveActive = true;
          notifyListeners();
          onLiveStart?.call();
          break;
        case 'LIVE_STOP':
          _liveActive = false;
          notifyListeners();
          onLiveStop?.call();
          break;
        case 'PONG':
          // connection alive
          break;
        case 'ACK':
          onAckReceived?.call(msg['id'] ?? '');
          break;
        case 'OPEN':
          _status = ConnectionStatus.connected;
          notifyListeners();
          break;
        case 'ERROR':
          onError?.call(msg['msg'] ?? 'Server xatosi');
          break;
      }
    } catch (e) {
      debugPrint('PeerService parse error: $e');
    }
  }

  void _sendAck(String id) {
    _send({'type': 'ACK', 'id': id});
  }

  Future<void> sendPattern(VibrationPattern pattern, String targetId) async {
    if (!isConnected) {
      onError?.call('Ulanish yo\'q. Qurilma oflayn.');
      return;
    }
    final msgId = DateTime.now().millisecondsSinceEpoch.toString();
    _send({
      'type': 'VIBE',
      'id': msgId,
      'to': targetId,
      'pattern': pattern.toJson(),
    });
    onAckReceived?.call('sent:$msgId');
  }

  void sendLiveStart(String targetId) {
    _send({'type': 'LIVE_START', 'to': targetId});
  }

  void sendLiveStop(String targetId) {
    _send({'type': 'LIVE_STOP', 'to': targetId});
  }

  void _send(Map<String, dynamic> data) {
    try {
      _channel?.sink.add(jsonEncode(data));
    } catch (e) {
      debugPrint('Send error: $e');
    }
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_status == ConnectionStatus.connected) {
        _send({'type': 'PING'});
      }
    });
  }

  void _onError(dynamic err) {
    _status = ConnectionStatus.disconnected;
    notifyListeners();
    onError?.call('Tarmoq xatosi. Qayta ulanilmoqda...');
    _scheduleReconnect();
  }

  void _onDisconnect() {
    _status = ConnectionStatus.disconnected;
    if (_liveActive) {
      _liveActive = false;
      onLiveStop?.call();
    }
    notifyListeners();
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (_targetPeerId != null && _status == ConnectionStatus.disconnected) {
        connect(_targetPeerId!);
      }
    });
  }

  void setTarget(String peerId) {
    _targetPeerId = peerId;
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    super.dispose();
  }
}
