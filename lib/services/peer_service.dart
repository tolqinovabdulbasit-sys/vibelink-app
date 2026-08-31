import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/vibration_pattern.dart';
import 'relay_backend.dart';

enum ConnectionStatus { disconnected, connecting, connected }

class PeerService extends ChangeNotifier {
  RelayBackend? _backend;
  RelayType _relayType = RelayType.cloudPubNub;
  ConnectionStatus _status = ConnectionStatus.disconnected;
  String _myId = '';
  String _currentChannel = '';
  String? _targetPeerId;

  Timer? _pingTimer;
  Timer? _reconnectTimer;
  Timer? _liveWatchdog;
  bool _isLive = false;
  DateTime? _lastPeerSeen;

  // Delivery status tracking (100% honest ACK confirmation)
  String _deliveryStatus = 'idle'; // 'idle', 'sending', 'delivered', 'failed'
  String _lastDeliveredTime = '';
  final Map<String, Timer> _ackTimeouts = {};

  String get deliveryStatus => _deliveryStatus;
  String get lastDeliveredTime => _lastDeliveredTime;

  static String getPairChannel(String id1, String id2) {
    final a = id1.trim().replaceAll(' ', '').toUpperCase();
    final b = id2.trim().replaceAll(' ', '').toUpperCase();
    final list = [a, b]..sort();
    return 'pair_${list[0]}_${list[1]}';
  }

  bool get isPeerOnline =>
      _lastPeerSeen != null &&
      DateTime.now().difference(_lastPeerSeen!).inSeconds < 7;

  ConnectionStatus get status => _status;
  bool get isConnected => _status == ConnectionStatus.connected;
  bool get isLive => _isLive;
  String get currentChannel => _currentChannel;
  RelayType get relayType => _relayType;
  String? get targetPeerId => _targetPeerId;

  Function(VibrationPattern)? onVibeReceived;
  Function()? onLiveStart;
  Function()? onLiveStop;
  Function(String status, String timeStr)? onDeliveryStatusChanged;
  Function(String peerId, String name)? onPeerJoined;
  Function(String status)? onPeerStatusChanged;
  Function(String)? onError;

  // ──────────────────────────────────────────────
  // Initialization
  // ──────────────────────────────────────────────

  Future<void> init(String myPeerId) async {
    _myId = myPeerId.trim().toUpperCase();
    final prefs = await SharedPreferences.getInstance();
    final savedType = prefs.getString('relay_type') ?? 'cloudPubNub';
    _relayType = RelayTypeMeta.fromKey(savedType);
  }

  // ──────────────────────────────────────────────
  // Switch backend (from Settings UI)
  // ──────────────────────────────────────────────

  Future<void> switchBackend(RelayType newType) async {
    if (_relayType == newType && _backend != null && _backend!.isConnected) return;
    _relayType = newType;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('relay_type', newType.key);
    if (_currentChannel.isNotEmpty) {
      await joinChannel(_currentChannel);
    }
    notifyListeners();
  }

  // ──────────────────────────────────────────────
  // Join Channel
  // ──────────────────────────────────────────────

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
    final cleanPeer = peerId.trim().replaceAll(' ', '').toUpperCase();
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

    if (fromId == _myId) return;

    if (ts > 0) {
      final msgTime = DateTime.fromMillisecondsSinceEpoch(ts);
      if (DateTime.now().difference(msgTime).inSeconds > 6) return;
    }

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
        _publish({'type': 'PONG', 'fromId': _myId, 'ts': DateTime.now().millisecondsSinceEpoch});
        break;

      case 'PONG':
        break;

      case 'ACK':
        final id = data['id'] as String? ?? '';
        if (id.isNotEmpty && _ackTimeouts.containsKey(id)) {
          _ackTimeouts[id]?.cancel();
          _ackTimeouts.remove(id);

          final now = DateTime.now();
          _lastDeliveredTime = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";
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
  // Public API with Honest ACK Confirmation
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
    _pingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_status == ConnectionStatus.connected && _currentChannel.isNotEmpty) sendPing();
      if (_lastPeerSeen != null &&
          DateTime.now().difference(_lastPeerSeen!).inSeconds >= 7) {
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
    _targetPeerId = peerId.trim().toUpperCase();
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
      backend.onConnected = () { if (!completer.isCompleted) completer.complete(true); };
      backend.onDisconnected = () { if (!completer.isCompleted) completer.complete(false); };
      await backend.connect(testCh);
      final result = await completer.future.timeout(const Duration(seconds: 5), onTimeout: () => false);
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
