import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/vibration_pattern.dart';
import 'relay_backend.dart';

enum ConnectionStatus { disconnected, connecting, connected }

class PeerService extends ChangeNotifier {
  RelayBackend? _backend;
  RelayType _relayType = RelayType.websocket;
  ConnectionStatus _status = ConnectionStatus.disconnected;
  String _myId = '';
  String _currentChannel = '';
  String? _targetPeerId;

  Timer? _pingTimer;
  Timer? _reconnectTimer;
  Timer? _liveWatchdog;
  bool _isLive = false;
  DateTime? _lastPeerSeen;

  // Public getters
  bool get isPeerOnline =>
      _lastPeerSeen != null &&
      DateTime.now().difference(_lastPeerSeen!).inSeconds < 8;

  ConnectionStatus get status => _status;
  bool get isConnected => _status == ConnectionStatus.connected;
  bool get isLive => _isLive;
  String get currentChannel => _currentChannel;
  RelayType get relayType => _relayType;

  // Callbacks
  Function(VibrationPattern)? onVibeReceived;
  Function()? onLiveStart;
  Function()? onLiveStop;
  Function(String)? onAckReceived;
  Function(String peerId, String name)? onPeerJoined;
  Function(String status)? onPeerStatusChanged;
  Function(String)? onError;

  // ──────────────────────────────────────────────
  // Initialization
  // ──────────────────────────────────────────────

  Future<void> init(String myPeerId) async {
    _myId = myPeerId;
    // Load saved relay type
    final prefs = await SharedPreferences.getInstance();
    final savedType = prefs.getString('relay_type') ?? 'websocket';
    _relayType = RelayTypeMeta.fromKey(savedType);
  }

  // ──────────────────────────────────────────────
  // Switch backend (from Settings)
  // ──────────────────────────────────────────────

  Future<void> switchBackend(RelayType newType) async {
    if (_relayType == newType && _backend != null) return;

    _relayType = newType;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('relay_type', newType.key);

    // Reconnect with new backend if already in a channel
    if (_currentChannel.isNotEmpty) {
      await joinChannel(_currentChannel);
    }
    notifyListeners();
  }

  // ──────────────────────────────────────────────
  // Join channel / room
  // ──────────────────────────────────────────────

  Future<void> joinChannel(String channelCode) async {
    final cleanCode = channelCode.trim().replaceAll(' ', '').toUpperCase();
    if (cleanCode.isEmpty) return;

    _currentChannel = cleanCode;
    _status = ConnectionStatus.connecting;
    notifyListeners();

    // Tear down old backend
    _backend?.disconnect();

    // Create fresh backend of the selected type
    _backend = createBackend(_relayType);

    _backend!.onMessage = (data) => _handleData(data);
    _backend!.onConnected = () {
      _status = ConnectionStatus.connected;
      notifyListeners();
      debugPrint('[PEER] Connected via ${_relayType.shortLabel} to channel: $cleanCode');
    };
    _backend!.onDisconnected = () {
      _status = ConnectionStatus.disconnected;
      notifyListeners();
      debugPrint('[PEER] Disconnected. Scheduling reconnect...');
      _scheduleReconnect();
    };

    try {
      await _backend!.connect(cleanCode);
      if (_backend!.isConnected) {
        _status = ConnectionStatus.connected;
      }
    } catch (e) {
      debugPrint('[PEER] Join error: $e');
      _status = ConnectionStatus.disconnected;
      _scheduleReconnect();
    }
    notifyListeners();

    // Start ping loop
    sendPing();
    _startPingTimer();
  }

  // ──────────────────────────────────────────────
  // Handle incoming data
  // ──────────────────────────────────────────────

  void _handleData(Map<String, dynamic> data) {
    final fromId = data['fromId'] as String? ?? '';
    final type = data['type'] as String? ?? '';

    // Ignore own messages
    if (fromId == _myId) return;

    _lastPeerSeen = DateTime.now();
    onPeerStatusChanged?.call('online');
    notifyListeners();

    switch (type) {
      case 'HELLO':
        final name = data['name'] as String? ?? 'Sherik';
        onPeerJoined?.call(fromId, name);
        _publish({
          'type': 'HELLO_ACK',
          'fromId': _myId,
          'name': 'Mening Telefonim',
        });
        break;

      case 'HELLO_ACK':
        final name = data['name'] as String? ?? 'Sherik';
        onPeerJoined?.call(fromId, name);
        break;

      case 'VIBE':
        final patternData = data['pattern'] as Map<String, dynamic>?;
        if (patternData != null) {
          final pattern = VibrationPattern.fromJson(patternData);
          onVibeReceived?.call(pattern);
        }
        final msgId = data['id'] as String? ?? '';
        if (msgId.isNotEmpty) {
          _publish({
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
        _publish({
          'type': 'PONG',
          'fromId': _myId,
        });
        break;

      case 'PONG':
        // Peer is alive — already tracked above
        break;

      case 'ACK':
        final id = data['id'] as String? ?? '';
        onAckReceived?.call(id);
        break;
    }
  }

  void _resetLiveWatchdog() {
    _liveWatchdog?.cancel();
    _liveWatchdog = Timer(const Duration(milliseconds: 400), () {
      if (_isLive) {
        _isLive = false;
        notifyListeners();
        onLiveStop?.call();
      }
    });
  }

  // ──────────────────────────────────────────────
  // Publish via selected backend
  // ──────────────────────────────────────────────

  Future<void> _publish(Map<String, dynamic> data) async {
    if (_backend == null || _currentChannel.isEmpty) return;
    await _backend!.publish(data);
  }

  // ──────────────────────────────────────────────
  // Outgoing messages
  // ──────────────────────────────────────────────

  void sendHello(String myName) {
    _publish({
      'type': 'HELLO',
      'fromId': _myId,
      'name': myName,
    });
  }

  void sendPattern(VibrationPattern pattern, String targetId) {
    final msgId = DateTime.now().millisecondsSinceEpoch.toString();
    _publish({
      'type': 'VIBE',
      'id': msgId,
      'fromId': _myId,
      'pattern': pattern.toJson(),
    });
    onAckReceived?.call('sent:$msgId');
  }

  void sendLiveStart(String targetId) {
    _publish({'type': 'LIVE_START', 'fromId': _myId});
  }

  void sendLiveTick(String targetId) {
    _publish({'type': 'LIVE_TICK', 'fromId': _myId});
  }

  void sendLiveStop(String targetId) {
    _publish({'type': 'LIVE_STOP', 'fromId': _myId});
  }

  void sendPing() {
    _publish({'type': 'PING', 'fromId': _myId});
  }

  // ──────────────────────────────────────────────
  // Ping timer & reconnect
  // ──────────────────────────────────────────────

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_status == ConnectionStatus.connected && _currentChannel.isNotEmpty) {
        sendPing();
      }
      if (_lastPeerSeen != null &&
          DateTime.now().difference(_lastPeerSeen!).inSeconds >= 7) {
        onPeerStatusChanged?.call('offline');
        notifyListeners();
      }
    });
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (_currentChannel.isNotEmpty) {
        joinChannel(_currentChannel);
      }
    });
  }

  void setTarget(String peerId) {
    _targetPeerId = peerId;
    notifyListeners();
  }

  // ──────────────────────────────────────────────
  // Connection test (for Settings UI)
  // ──────────────────────────────────────────────

  Future<bool> testBackend(RelayType type) async {
    try {
      final testCh = 'test_${DateTime.now().millisecondsSinceEpoch}';
      final backend = createBackend(type);
      final completer = Completer<bool>();

      backend.onConnected = () {
        if (!completer.isCompleted) completer.complete(true);
      };
      backend.onDisconnected = () {
        if (!completer.isCompleted) completer.complete(false);
      };

      await backend.connect(testCh);

      // Wait up to 6 seconds
      final result = await completer.future.timeout(
        const Duration(seconds: 6),
        onTimeout: () => false,
      );

      backend.disconnect();
      return result;
    } catch (e) {
      return false;
    }
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _liveWatchdog?.cancel();
    _backend?.disconnect();
    super.dispose();
  }
}
