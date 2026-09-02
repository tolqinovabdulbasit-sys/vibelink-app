import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/vibration_pattern.dart';
import 'relay_backend.dart';

enum ConnectionStatus { disconnected, connecting, connected }

class PeerService extends ChangeNotifier {
  String _myId = '';
  String? _targetPeerId;
  String _currentChannel = '';
  ConnectionStatus _status = ConnectionStatus.disconnected;
  RelayBackend? _backend;
  RelayType _relayType = RelayType.cloudPubNub;

  // Status & Watchdog
  DateTime? _lastPeerSeen;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  Timer? _liveWatchdog;
  bool _isLive = false;

  // Reliable Delivery & ACK Confirmation
  String _deliveryStatus = 'idle'; // 'idle', 'sending', 'delivered', 'failed'
  String _lastDeliveredTime = '';
  final Map<String, Timer> _ackTimeouts = {};

  // Callbacks
  void Function(VibrationPattern pattern)? onVibeReceived;
  void Function()? onLiveStart;
  void Function()? onLiveStop;
  void Function(String status)? onPeerStatusChanged; // 'online' | 'offline'
  void Function(String peerId, String name)? onPeerJoined;
  void Function(String status, String timeStr)? onDeliveryStatusChanged;

  String get myId => _myId;
  String? get targetPeerId => _targetPeerId;
  String get currentChannel => _currentChannel;
  ConnectionStatus get status => _status;
  RelayType get relayType => _relayType;
  bool get isConnected => _status == ConnectionStatus.connected;
  bool get isLive => _isLive;
  String get deliveryStatus => _deliveryStatus;
  String get lastDeliveredTime => _lastDeliveredTime;

  static String getPairChannel(String a, String b) {
    final cleanA = a.trim().padLeft(2, '0').toUpperCase();
    final cleanB = b.trim().padLeft(2, '0').toUpperCase();
    final sorted = [cleanA, cleanB]..sort();
    return 'pair_${sorted[0]}_${sorted[1]}';
  }

  void init(String myId) {
    _myId = myId.trim().padLeft(2, '0').toUpperCase();
    notifyListeners();
  }

  void setRelayType(RelayType type) {
    if (_relayType == type) return;
    _relayType = type;
    notifyListeners();
    if (_currentChannel.isNotEmpty) {
      joinChannel(_currentChannel);
    }
  }

  Future<void> joinChannel(String channel) async {
    if (channel.isEmpty) return;
    _currentChannel = channel;
    _status = ConnectionStatus.connecting;
    notifyListeners();

    _backend?.disconnect();
    _backend = createBackend(_relayType);

    _backend!.onConnected = () {
      _status = ConnectionStatus.connected;
      notifyListeners();
      // Instantly announce online presence to peer
      sendPing();
    };
    _backend!.onDisconnected = () {
      _status = ConnectionStatus.disconnected;
      notifyListeners();
      _scheduleReconnect();
    };
    _backend!.onMessage = _handleData;

    try {
      await _backend!.connect(channel);
    } catch (e) {
      debugPrint('[PEER] Join error: $e');
      _status = ConnectionStatus.disconnected;
      _scheduleReconnect();
    }
    notifyListeners();
    _startPingTimer();
  }

  Future<void> connectWithPeer(String peerId) async {
    final cleanPeer = peerId.trim().padLeft(2, '0').toUpperCase();
    if (cleanPeer.isEmpty || _myId.isEmpty) return;
    _targetPeerId = cleanPeer;
    final sharedChannel = getPairChannel(_myId, cleanPeer);
    await joinChannel(sharedChannel);
  }

  // ──────────────────────────────────────────────
  // Handle incoming data
  // ──────────────────────────────────────────────

  void _handleData(Map<String, dynamic> data) {
    final fromId = (data['fromId'] as String? ?? '').trim().toUpperCase();
    final type = data['type'] as String? ?? '';
    final ts = data['ts'] as int? ?? 0;

    // Filter out our own messages
    if (fromId == _myId) return;

    if (ts > 0) {
      final msgTime = DateTime.fromMillisecondsSinceEpoch(ts);
      if (DateTime.now().difference(msgTime).inSeconds > 6) return;
    }

    // Update peer liveness
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
          'name': 'Sherik Telefon',
          'ts': DateTime.now().millisecondsSinceEpoch,
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
            'ts': DateTime.now().millisecondsSinceEpoch,
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
          'ts': DateTime.now().millisecondsSinceEpoch,
        });
        break;

      case 'PONG':
        // Peer is verified online
        break;

      case 'ACK':
        final id = data['id'] as String? ?? '';
        if (id.isNotEmpty && _ackTimeouts.containsKey(id)) {
          _ackTimeouts[id]?.cancel();
          _ackTimeouts.remove(id);

          final now = DateTime.now();
          _lastDeliveredTime =
              "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";
          _deliveryStatus = 'delivered';
          notifyListeners();
          onDeliveryStatusChanged?.call('delivered', _lastDeliveredTime);
        }
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
  // Publish
  // ──────────────────────────────────────────────

  Future<void> _publish(Map<String, dynamic> data) async {
    if (_currentChannel.isEmpty) return;
    data['ts'] = DateTime.now().millisecondsSinceEpoch;
    _backend?.publish(data);
  }

  // ──────────────────────────────────────────────
  // Public API
  // ──────────────────────────────────────────────

  void sendHello(String myName) {
    _publish({'type': 'HELLO', 'fromId': _myId, 'name': myName});
  }

  void sendPattern(VibrationPattern pattern, String targetId) {
    final msgId = DateTime.now().millisecondsSinceEpoch.toString();

    // Set status to sending
    _deliveryStatus = 'sending';
    notifyListeners();
    onDeliveryStatusChanged?.call('sending', '');

    // Set 3.5s timeout for ACK
    _ackTimeouts[msgId] = Timer(const Duration(milliseconds: 3500), () {
      _ackTimeouts.remove(msgId);
      if (_deliveryStatus == 'sending') {
        _deliveryStatus = 'failed';
        notifyListeners();
        onDeliveryStatusChanged?.call('failed', '');
      }
    });

    _publish({
      'type': 'VIBE',
      'id': msgId,
      'fromId': _myId,
      'pattern': pattern.toJson(),
    });
  }

  void sendLiveStart(String targetId) => _publish({'type': 'LIVE_START', 'fromId': _myId});
  void sendLiveTick(String targetId) => _publish({'type': 'LIVE_TICK', 'fromId': _myId});
  void sendLiveStop(String targetId) => _publish({'type': 'LIVE_STOP', 'fromId': _myId});
  void sendPing() => _publish({'type': 'PING', 'fromId': _myId});

  void _startPingTimer() {
    _pingTimer?.cancel();
    // Ping every 2 seconds for ultra-responsive online detection
    _pingTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_status == ConnectionStatus.connected && _currentChannel.isNotEmpty) {
        sendPing();
      }
      // If no response from peer for 5 seconds, declare offline
      if (_lastPeerSeen != null &&
          DateTime.now().difference(_lastPeerSeen!).inSeconds >= 5) {
        onPeerStatusChanged?.call('offline');
        notifyListeners();
      }
    });
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 2), () {
      if (_currentChannel.isNotEmpty) joinChannel(_currentChannel);
    });
  }

  void setTarget(String peerId) {
    _targetPeerId = peerId.trim().padLeft(2, '0').toUpperCase();
    if (_myId.isNotEmpty && _targetPeerId!.isNotEmpty) {
      connectWithPeer(_targetPeerId!);
    }
    notifyListeners();
  }

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
      final result =
          await completer.future.timeout(const Duration(seconds: 5), onTimeout: () => false);
      backend.disconnect();
      return result;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _liveWatchdog?.cancel();
    for (final timer in _ackTimeouts.values) {
      timer.cancel();
    }
    _ackTimeouts.clear();
    _backend?.disconnect();
    super.dispose();
  }
}
