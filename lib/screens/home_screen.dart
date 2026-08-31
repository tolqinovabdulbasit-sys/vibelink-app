import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/device_service.dart';
import '../services/vibration_service.dart';
import '../services/peer_service.dart';
import '../models/vibration_pattern.dart';
import '../widgets/preset_card.dart';
import '../widgets/history_tile.dart';
import '../widgets/connection_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  VibrationPattern? _selectedPreset;
  bool _isHoldingLive = false;
  Timer? _liveTickTimer;
  
  // 100% Honest ACK & Delivery Status
  String _deliveryStatus = 'idle'; // 'idle', 'sending', 'delivered', 'failed'
  String _lastDeliveredTime = '';
  Timer? _deliveryResetTimer;

  // Custom visible pattern IDs set by user in Settings
  List<String> _visiblePatternIds = [];

  @override
  void initState() {
    super.initState();
    _selectedPreset = kBuiltinPresets.first;
    _loadVisiblePatterns();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupPeerCallbacks();
    });
  }

  Future<void> _loadVisiblePatterns() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('home_visible_patterns');
    if (mounted) {
      setState(() {
        if (saved != null && saved.isNotEmpty) {
          _visiblePatternIds = List<String>.from(saved);
        } else {
          _visiblePatternIds = kBuiltinPresets.map((p) => p.id).toList();
        }
      });
    }
  }

  void _setupPeerCallbacks() {
    final peerService = context.read<PeerService>();
    final vibeService = context.read<VibrationService>();
    final devService = context.read<DeviceService>();

    peerService.init(devService.myDeviceId);

    if (devService.activeDevice != null) {
      peerService.connectWithPeer(devService.activeDevice!.id);
    }

    peerService.onVibeReceived = (pattern) {
      final active = devService.activeDevice;
      vibeService.playPattern(pattern, deviceName: active?.name ?? 'Sherik');
    };

    peerService.onLiveStart = () => vibeService.startLive();
    peerService.onLiveStop = () => vibeService.stopLive();

    peerService.onDeliveryStatusChanged = (status, timeStr) {
      if (!mounted) return;
      setState(() {
        _deliveryStatus = status;
        if (timeStr.isNotEmpty) _lastDeliveredTime = timeStr;
      });

      if (status == 'delivered') {
        HapticFeedback.lightImpact();
        _deliveryResetTimer?.cancel();
        _deliveryResetTimer = Timer(const Duration(seconds: 4), () {
          if (mounted) setState(() => _deliveryStatus = 'idle');
        });
      } else if (status == 'failed') {
        HapticFeedback.vibrate();
        _deliveryResetTimer?.cancel();
        _deliveryResetTimer = Timer(const Duration(seconds: 4), () {
          if (mounted) setState(() => _deliveryStatus = 'idle');
        });
      }
    };

    peerService.onPeerStatusChanged = (status) {
      if (devService.activeDevice != null) {
        devService.updateDeviceStatus(devService.activeDevice!.id, status);
      }
    };
  }

  void _sendPattern(VibrationPattern pattern) {
    final deviceService = context.read<DeviceService>();
    final peerService = context.read<PeerService>();
    final active = deviceService.activeDevice;

    if (active == null) {
      _showToast("Qurilma ulanmagan! 'Sozlamalar' bo'limidan qo'shing.");
      return;
    }

    final sharedChannel = PeerService.getPairChannel(deviceService.myDeviceId, active.id);
    if (peerService.currentChannel != sharedChannel) {
      peerService.connectWithPeer(active.id);
    }

    setState(() {
      _selectedPreset = pattern;
      _deliveryStatus = 'sending';
    });

    peerService.sendPattern(pattern, active.id);
  }

  void _onLiveTouchStart() {
    final deviceService = context.read<DeviceService>();
    final peerService = context.read<PeerService>();
    final active = deviceService.activeDevice;

    if (active == null) return;
    HapticFeedback.selectionClick();

    setState(() => _isHoldingLive = true);
    peerService.sendLiveStart(active.id);

    _liveTickTimer?.cancel();
    _liveTickTimer = Timer.periodic(const Duration(milliseconds: 150), (_) {
      if (_isHoldingLive) {
        peerService.sendLiveTick(active.id);
      }
    });
  }

  void _onLiveTouchEnd() {
    if (!_isHoldingLive) return;
    _liveTickTimer?.cancel();
    _liveTickTimer = null;

    final deviceService = context.read<DeviceService>();
    final peerService = context.read<PeerService>();
    final active = deviceService.activeDevice;

    setState(() => _isHoldingLive = false);
    if (active != null) {
      peerService.sendLiveStop(active.id);
    }
  }

  void _showToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFF6C63FF),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showAllHistory() {
    final vibeService = context.read<VibrationService>();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF12122A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text('Signal Tarixi', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Expanded(
              child: vibeService.history.isEmpty
                  ? Center(child: Text('Tarix bo\'sh', style: TextStyle(color: Colors.white.withOpacity(0.4))))
                  : ListView.builder(
                      itemCount: vibeService.history.length,
                      itemBuilder: (_, i) => HistoryTile(history: vibeService.history[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  List<VibrationPattern> get _displayedPresets {
    if (_visiblePatternIds.isEmpty) return kBuiltinPresets;
    final filtered = kBuiltinPresets.where((p) => _visiblePatternIds.contains(p.id)).toList();
    return filtered.isNotEmpty ? filtered : kBuiltinPresets;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(),
            const ConnectionCard(),
            if (_deliveryStatus != 'idle') _buildDeliveryStatusBanner(),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: [
                    _buildPresetsSection(),
                    _buildLiveTouchArea(),
                    _buildHistorySection(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.vibration_rounded, color: Color(0xFF6C63FF), size: 24),
          SizedBox(width: 8),
          Text(
            'VibeLink',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }

  // 100% Honest ACK & Delivery Status Banner
  Widget _buildDeliveryStatusBanner() {
    Color bg;
    Color border;
    IconData icon;
    String text;

    if (_deliveryStatus == 'sending') {
      bg = const Color(0xFF3B82F6).withOpacity(0.15);
      border = const Color(0xFF3B82F6).withOpacity(0.4);
      icon = Icons.send_rounded;
      text = '✉️ 2-telefonga yuborilmoqda... (Kutilmoqda)';
    } else if (_deliveryStatus == 'delivered') {
      bg = const Color(0xFF22C55E).withOpacity(0.15);
      border = const Color(0xFF22C55E).withOpacity(0.4);
      icon = Icons.check_circle_rounded;
      text = '✅ 2-telefonga yetib bordi! ($_lastDeliveredTime)';
    } else {
      bg = const Color(0xFFEF4444).withOpacity(0.15);
      border = const Color(0xFFEF4444).withOpacity(0.4);
      icon = Icons.error_outline_rounded;
      text = '⚠️ Yetib bormadi (Sherik javob bermadi)';
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          if (_deliveryStatus == 'sending')
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF3B82F6)),
            )
          else
            Icon(icon, color: border, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetsSection() {
    final presets = _displayedPresets;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Text(
            'Tez Signallar (Bir marta bosing)',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
        SizedBox(
          height: 94,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(left: 16),
            itemCount: presets.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.only(right: 10),
              child: PresetCard(
                pattern: presets[i],
                isSelected: _selectedPreset?.id == presets[i].id,
                onTap: () => _sendPattern(presets[i]),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLiveTouchArea() {
    final presets = _displayedPresets;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF12122A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
      ),
      child: Row(
        children: [
          Listener(
            onPointerDown: (_) => _onLiveTouchStart(),
            onPointerUp: (_) => _onLiveTouchEnd(),
            onPointerCancel: (_) => _onLiveTouchEnd(),
            child: Column(
              children: [
                Container(
                  width: 95,
                  height: 95,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: _isHoldingLive
                          ? [const Color(0xFF6C63FF), const Color(0xFF3B82F6)]
                          : [const Color(0xFF232348), const Color(0xFF16162E)],
                    ),
                    boxShadow: _isHoldingLive
                        ? [
                            BoxShadow(
                              color: const Color(0xFF6C63FF).withOpacity(0.7),
                              blurRadius: 20,
                              spreadRadius: 4,
                            ),
                          ]
                        : [],
                  ),
                  child: Icon(
                    Icons.touch_app_rounded,
                    color: _isHoldingLive ? Colors.white : Colors.white70,
                    size: 38,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _isHoldingLive ? 'Yuborilmoqda...' : 'Bosib ushlang',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: _isHoldingLive ? FontWeight.w700 : FontWeight.w500,
                    color: _isHoldingLive ? const Color(0xFF6C63FF) : Colors.white54,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: presets.take(4).map((p) {
                final color = Color(int.parse(p.colorHex.replaceFirst('#', '0xFF')));
                return InkWell(
                  onTap: () => _sendPattern(p),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: color,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            p.name,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withOpacity(0.85),
                            ),
                          ),
                        ),
                        Icon(Icons.send_rounded, size: 14, color: color.withOpacity(0.7)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistorySection() {
    return Consumer<VibrationService>(
      builder: (_, vibe, __) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Tarix',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                InkWell(
                  onTap: _showAllHistory,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text(
                      'Hammasi',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6C63FF),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (vibe.history.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text(
                  'Tarix bo\'sh',
                  style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12),
                ),
              ),
            )
          else
            ...vibe.history.take(3).map((h) => HistoryTile(history: h)),
        ],
      ),
    );
  }
}
