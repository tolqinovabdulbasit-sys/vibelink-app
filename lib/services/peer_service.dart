import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import '../models/vibration_pattern.dart';

enum ConnectionStatus { disconnected, connecting, connected }

class PeerService extends ChangeNotifier {
  MqttServerClient? _client;
  ConnectionStatus _status = ConnectionStatus.disconnected;
  String _myId = '';
  String? _targetPeerId;
  String? _currentPairTopic;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  Timer? _liveWatchdog;
  bool _isLive = false;

  ConnectionStatus get status => _status;
  bool get isConnected => _status == ConnectionStatus.connected;
  bool get isLive => _isLive;
  String? get targetPeerId => _targetPeerId;

  // Callbacks
  Function(VibrationPattern)? onVibeReceived;
  Function()? onLiveStart;
  Function()? onLiveStop;
  Function(String)? onAckReceived;
  Function(String peerId, String name)? onPairRequestReceived;
  Function(String peerId, String name)? onPairAccepted;
  Function(String status)? onPeerStatusChanged;
  Function(String)? onError;

  DateTime? _lastPongReceived;
  bool get isPeerOnline =>
      _lastPongReceived != null &&
      DateTime.now().difference(_lastPongReceived!).inSeconds < 10;

  Future<void> connect(String myPeerId) async {
    if (_status == ConnectionStatus.connecting) return;
    _myId = myPeerId;
    _status = ConnectionStatus.connecting;
    notifyListeners();

    try {
      _client?.disconnect();
      final clientId = 'VL_${_myId}_${DateTime.now().millisecondsSinceEpoch % 10000}';
      
      // Use broker.emqx.io with WSS port 8084 (SSL/TLS WebSocket - ultra low latency)
      _client = MqttServerClient.withPort('broker.emqx.io', clientId, 8084);
      _client!.useWebSocket = true;
      _client!.websocketProtocols = MqttClientConstants.protocolsSingleDefault;
      _client!.secure = true;
      _client!.keepAlivePeriod = 20;
      _client!.autoReconnect = true;
      _client!.logging(on: false);

      final connMessage = MqttConnectMessage()
          .withClientIdentifier(clientId)
          .startClean()
          .withWillQos(MqttQos.atMostOnce);
      _client!.connectionMessage = connMessage;

      final result = await _client!.connect().timeout(const Duration(seconds: 8));

      if (result?.state == MqttConnectionState.connected) {
        _status = ConnectionStatus.connected;
        notifyListeners();
        _subscribeToMyTopic();
        _startListening();
        _startPing();
      } else {
        _fallbackConnect();
      }
    } catch (e) {
      debugPrint('EMQX connect error: $e');
      _fallbackConnect();
    }
  }

  Future<void> _fallbackConnect() async {
    try {
      final clientId = 'VL_${_myId}_${DateTime.now().millisecondsSinceEpoch % 10000}';
      _client = MqttServerClient.withPort('broker.hivemq.com', clientId, 8000);
      _client!.useWebSocket = true;
      _client!.websocketProtocols = MqttClientConstants.protocolsSingleDefault;
      _client!.secure = false;
      _client!.keepAlivePeriod = 20;
      _client!.autoReconnect = true;
      _client!.logging(on: false);

      final connMessage = MqttConnectMessage()
          .withClientIdentifier(clientId)
          .startClean();
      _client!.connectionMessage = connMessage;

      final result = await _client!.connect().timeout(const Duration(seconds: 8));
      if (result?.state == MqttConnectionState.connected) {
        _status = ConnectionStatus.connected;
        notifyListeners();
        _subscribeToMyTopic();
        _startListening();
        _startPing();
      } else {
        _status = ConnectionStatus.disconnected;
        notifyListeners();
        _scheduleReconnect();
      }
    } catch (e) {
      _status = ConnectionStatus.disconnected;
      notifyListeners();
      _scheduleReconnect();
    }
  }

  void _subscribeToMyTopic() {
    if (_client?.connectionStatus?.state == MqttConnectionState.connected) {
      final topic = 'vibelink/dev/$_myId';
      _client!.subscribe(topic, MqttQos.atMostOnce);
      debugPrint('Subscribed to $topic');
    }
  }

  void listenToPairCode(String code) {
    if (_currentPairTopic != null && _currentPairTopic != 'vibelink/pair/$code') {
      _client?.unsubscribe(_currentPairTopic!);
    }
    _currentPairTopic = 'vibelink/pair/$code';
    if (_client?.connectionStatus?.state == MqttConnectionState.connected) {
      _client!.subscribe(_currentPairTopic!, MqttQos.atMostOnce);
    }
  }

  void unlistenPairCode() {
    if (_currentPairTopic != null) {
      _client?.unsubscribe(_currentPairTopic!);
      _currentPairTopic = null;
    }
  }

  void _startListening() {
    _client?.updates?.listen((List<MqttReceivedMessage<MqttMessage>> messages) {
      for (final msg in messages) {
        try {
          final recMessage = msg.payload as MqttPublishMessage;
          final payloadStr = MqttPublishPayload.bytesToStringAsString(recMessage.payload.message);
          final data = jsonDecode(payloadStr) as Map<String, dynamic>;
          _handleMessage(data, msg.topic);
        } catch (e) {
          debugPrint('MQTT parse error: $e');
        }
      }
    });
  }

  void _handleMessage(Map<String, dynamic> data, String topic) {
    final type = data['type'] as String? ?? '';
    final fromId = data['fromId'] as String? ?? '';

    // Prevent echoing own messages
    if (fromId == _myId && type != 'PING') return;

    switch (type) {
      case 'PAIR_REQ':
        final fromName = data['fromName'] as String? ?? 'Qurilma';
        onPairRequestReceived?.call(fromId, fromName);
        // Automatically send PAIR_ACK back
        _publishToTopic('vibelink/dev/$fromId', {
          'type': 'PAIR_ACK',
          'fromId': _myId,
          'fromName': 'Sherik',
        });
        break;

      case 'PAIR_ACK':
        final name = data['fromName'] as String? ?? 'Qurilma';
        onPairAccepted?.call(fromId, name);
        break;

      case 'VIBE':
        final patternData = data['pattern'] as Map<String, dynamic>?;
        if (patternData != null) {
          final pattern = VibrationPattern.fromJson(patternData);
          onVibeReceived?.call(pattern);
        }
        final msgId = data['id'] as String? ?? '';
        if (msgId.isNotEmpty && fromId.isNotEmpty) {
          _publishToTopic('vibelink/dev/$fromId', {
            'type': 'ACK',
            'id': msgId,
            'fromId': _myId,
          });
        }
        break;

      case 'LIVE_START':
        _isLive = true;
        notifyListeners();
        onLiveStart?.call();
        _resetLiveWatchdog();
        break;

      case 'LIVE_TICK':
        if (!_isLive) {
          _isLive = true;
          notifyListeners();
          onLiveStart?.call();
        }
        _resetLiveWatchdog();
        break;

      case 'LIVE_STOP':
        _isLive = false;
        _liveWatchdog?.cancel();
        notifyListeners();
        onLiveStop?.call();
        break;

      case 'PING':
        if (fromId.isNotEmpty) {
          _publishToTopic('vibelink/dev/$fromId', {
            'type': 'PONG',
            'fromId': _myId,
          });
        }
        break;

      case 'PONG':
        if (fromId == _targetPeerId) {
          _lastPongReceived = DateTime.now();
          onPeerStatusChanged?.call('online');
          notifyListeners();
        }
        break;

      case 'ACK':
        final id = data['id'] as String? ?? '';
        onAckReceived?.call(id);
        break;
    }
  }

  void _resetLiveWatchdog() {
    _liveWatchdog?.cancel();
    // If no live tick within 400ms, auto-stop to prevent sticking
    _liveWatchdog = Timer(const Duration(milliseconds: 400), () {
      if (_isLive) {
        _isLive = false;
        notifyListeners();
        onLiveStop?.call();
      }
    });
  }

  void setTarget(String peerId) {
    _targetPeerId = peerId;
    _lastPongReceived = null;
    _sendPing();
    notifyListeners();
  }

  // --- Immediate Low-Latency Transmission ---

  Future<void> sendPairRequest(String code, String myName) async {
    listenToPairCode(code);
    _publishToTopic('vibelink/pair/$code', {
      'type': 'PAIR_REQ',
      'fromId': _myId,
      'fromName': myName,
    });
  }

  Future<void> sendPattern(VibrationPattern pattern, String targetId) async {
    final msgId = DateTime.now().millisecondsSinceEpoch.toString();
    _publishToTopic('vibelink/dev/$targetId', {
      'type': 'VIBE',
      'id': msgId,
      'fromId': _myId,
      'pattern': pattern.toJson(),
    });
    onAckReceived?.call('sent:$msgId');
  }

  void sendLiveStart(String targetId) {
    _publishToTopic('vibelink/dev/$targetId', {
      'type': 'LIVE_START',
      'fromId': _myId,
    });
  }

  void sendLiveTick(String targetId) {
    _publishToTopic('vibelink/dev/$targetId', {
      'type': 'LIVE_TICK',
      'fromId': _myId,
    });
  }

  void sendLiveStop(String targetId) {
    _publishToTopic('vibelink/dev/$targetId', {
      'type': 'LIVE_STOP',
      'fromId': _myId,
    });
  }

  void _sendPing() {
    if (_targetPeerId != null && _targetPeerId!.isNotEmpty) {
      _publishToTopic('vibelink/dev/$_targetPeerId', {
        'type': 'PING',
        'fromId': _myId,
      });
    }
  }

  void _publishToTopic(String topic, Map<String, dynamic> data) {
    if (_client?.connectionStatus?.state == MqttConnectionState.connected) {
      final builder = MqttClientPayloadBuilder();
      builder.addString(jsonEncode(data));
      _client!.publishMessage(topic, MqttQos.atMostOnce, builder.payload!);
    } else {
      debugPrint('Cannot publish: MQTT disconnected');
      if (_status != ConnectionStatus.connecting) {
        connect(_myId);
      }
    }
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _sendPing();
      if (_lastPongReceived != null &&
          DateTime.now().difference(_lastPongReceived!).inSeconds >= 8) {
        onPeerStatusChanged?.call('offline');
        notifyListeners();
      }
    });
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 4), () {
      if (_status != ConnectionStatus.connected && _myId.isNotEmpty) {
        connect(_myId);
      }
    });
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _liveWatchdog?.cancel();
    _client?.disconnect();
    super.dispose();
  }
}
