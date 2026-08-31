import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/device_service.dart';
import '../services/vibration_service.dart';
import '../services/peer_service.dart';
import '../models/vibration_pattern.dart';
import '../widgets/preset_card.dart';
import '../widgets/ack_strip.dart';
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
  final List<String> _ackStates = ['idle', 'idle', 'idle', 'idle'];
  Timer? _ackResetTimer;
  String _lastDeliveredTime = '';

  @override
  void initState() {
    super.initState();
    _selectedPreset = kBuiltinPresets.first;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupPeerCallbacks();
    });
  }

  void _setupPeerCallbacks() {
    final peerService = context.read<PeerService>();
    final vibeService = context.read<VibrationService>();
    final devService = context.read<DeviceService>();

    peerService.init(devService.myDeviceId);

    // If already paired with active device, auto-join its room
    if (devService.activeDevice != null) {
      peerService.joinChannel(devService.activeDevice!.id);
    }

    peerService.onVibeReceived = (pattern) {
      final active = devService.activeDevice;
      vibeService.playPattern(pattern, deviceName: active?.name ?? 'Sherik');
    };

    peerService.onLiveStart = () => vibeService.startLive();
    peerService.onLiveStop = () => vibeService.stopLive();

    peerService.onAckReceived = (id) {
      if (!mounted) return;
      final now = DateTime.now();
      final timeStr = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";
      setState(() {
        _lastDeliveredTime = timeStr;
        _ackStates[0] = 'done';
        _ackStates[1] = 'done';
        _ackStates[2] = 'done';
        _ackStates[3] = 'done';
      });
      _ackResetTimer?.cancel();
      _ackResetTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() => _ackStates.fillRange(0, 4, 'idle'));
        }
      });
    };

    peerService.onPeerStatusChanged = (status) {
      if (devService.activeDevice != null) {
        devService.updateDeviceStatus(devService.activeDevice!.id, status);
      }
    };
  }

  // --- Instant Zero-Latency Send ---

  void _sendPattern(VibrationPattern pattern) {
    final deviceService = context.read<DeviceService>();
    final peerService = context.read<PeerService>();
    final active = deviceService.activeDevice;

    if (active == null) {
      _showToast("Qurilma ulanmagan! 'Устройства' bo'limidan qo'shing.");
      return;
    }

    // Make sure we are connected to the channel
    if (peerService.currentChannel != active.id) {
      peerService.joinChannel(active.id);
    }

    setState(() {
      _selectedPreset = pattern;
      _ackStates[0] = 'done';
      _ackStates[1] = 'loading';
      _ackStates[2] = 'idle';
      _ackStates[3] = 'idle';
    });

    peerService.sendPattern(pattern, active.id);

    Future.delayed(const Duration(milliseconds: 40), () {
      if (mounted) setState(() => _ackStates[1] = 'done');
    });
  }

  void _onLiveTouchStart() {
    final deviceService = context.read<DeviceService>();
    final peerService = context.read<PeerService>();
    final active = deviceService.activeDevice;

    if (active == null) {
      _showToast("Avval qurilma tanlang!");
      return;
    }

    if (peerService.currentChannel != active.id) {
      peerService.joinChannel(active.id);
    }

    setState(() => _isHoldingLive = true);
    HapticFeedback.mediumImpact();

    peerService.sendLiveStart(active.id);

    _liveTickTimer?.cancel();
    _liveTickTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      peerService.sendLiveTick(active.id);
    });
  }

  void _onLiveTouchEnd() {
    if (!_isHoldingLive) return;
    _liveTickTimer?.cancel();
    _liveTickTimer = null;
    setState(() => _isHoldingLive = false);

    final deviceService = context.read<DeviceService>();
    final peerService = context.read<PeerService>();
    final active = deviceService.activeDevice;

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

  void _showMenuDialog() {
    final ds = context.read<DeviceService>();
    final ps = context.read<PeerService>();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF12122A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.info_outline_rounded, color: Color(0xFF6C63FF)),
            SizedBox(width: 8),
            Text('VibeLink Info', style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Mening ID: ${ds.myDeviceId}',
              style: const TextStyle(color: Colors.white, fontFamily: 'JetBrains Mono', fontSize: 13)),
            const SizedBox(height: 8),
            Text('Kanal: ${ps.currentChannel.isNotEmpty ? ps.currentChannel : "Ulanmagan"}',
              style: const TextStyle(color: Color(0xFF00D4FF), fontFamily: 'JetBrains Mono', fontSize: 13)),
            const SizedBox(height: 8),
            Text('Holat: ${ps.isConnected ? "🟢 Serverga ulangan (HTTPS 443)" : "🔴 Ulanmagan"}',
              style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13)),
            const SizedBox(height: 8),
            Text('Sherik: ${ds.activeDevice != null ? ds.activeDevice!.name : "Tanlanmagan"} (${ps.isPeerOnline ? "🟢 Onlayn" : "⚪ Oflayn"})',
              style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Yopish', style: TextStyle(color: Color(0xFF6C63FF))),
          ),
        ],
      ),
    );
  }

  void _showProfileDialog() {
    final ds = context.read<DeviceService>();
    final nameCtrl = TextEditingController(text: ds.myDeviceName);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF12122A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Mening Profilim', style: TextStyle(color: Colors.white, fontSize: 18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Qurilma nomi', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
            const SizedBox(height: 6),
            TextField(
              controller: nameCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white.withOpacity(0.06),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
            Text('Qurilma IDsi', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
            const SizedBox(height: 4),
            InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: ds.myDeviceId));
                _showToast('ID nusxalandi');
              },
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(child: Text(ds.myDeviceId, style: const TextStyle(color: Color(0xFF00D4FF), fontFamily: 'JetBrains Mono', fontSize: 12))),
                    const Icon(Icons.copy_rounded, color: Colors.white54, size: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Bekor', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              if (nameCtrl.text.trim().isNotEmpty) {
                ds.setMyDeviceName(nameCtrl.text.trim());
              }
              Navigator.pop(context);
            },
            child: const Text('Saqlash', style: TextStyle(color: Color(0xFF6C63FF))),
          ),
        ],
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
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModalState) => Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Barcha Tarix', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
                  TextButton.icon(
                    onPressed: () async {
                      await vibeService.clearHistory();
                      setModalState(() {});
                      setState(() {});
                    },
                    icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 16),
                    label: const Text('Tozalash', style: TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
                  ),
                ],
              ),
              const Divider(color: Colors.white12),
              Expanded(
                child: vibeService.history.isEmpty
                    ? Center(child: Text("Tarix bo'sh", style: TextStyle(color: Colors.white.withOpacity(0.4))))
                    : ListView.builder(
                        itemCount: vibeService.history.length,
                        itemBuilder: (_, i) => HistoryTile(history: vibeService.history[i]),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _liveTickTimer?.cancel();
    _ackResetTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildHeader()),
          const SliverToBoxAdapter(child: ConnectionCard()),
          if (_lastDeliveredTime.isNotEmpty)
            SliverToBoxAdapter(child: _buildLastStatusCard()),
          SliverToBoxAdapter(child: _buildPresetsSection()),
          SliverToBoxAdapter(child: _buildLiveTouchArea()),
          SliverToBoxAdapter(child: AckStrip(states: _ackStates)),
          SliverToBoxAdapter(child: _buildHistorySection()),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: _showMenuDialog,
            icon: const Icon(Icons.menu_rounded, color: Colors.white, size: 24),
          ),
          const Text(
            'VibeLink',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.3,
            ),
          ),
          IconButton(
            onPressed: _showProfileDialog,
            icon: const Icon(Icons.person_rounded, color: Colors.white, size: 24),
          ),
        ],
      ),
    );
  }

  Widget _buildLastStatusCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF22C55E).withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF22C55E).withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: Color(0xFF22C55E), size: 18),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Vibratsiya ishga tushirildi', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
          ),
          Text(_lastDeliveredTime, style: const TextStyle(fontSize: 11, fontFamily: 'JetBrains Mono', color: Color(0xFF22C55E))),
        ],
      ),
    );
  }

  Widget _buildPresetsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Text(
            'Tez Signallar (Bir marta bosing)',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
        SizedBox(
          height: 100,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(left: 16),
            itemCount: kBuiltinPresets.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.only(right: 10),
              child: PresetCard(
                pattern: kBuiltinPresets[i],
                isSelected: _selectedPreset?.id == kBuiltinPresets[i].id,
                onTap: () => _sendPattern(kBuiltinPresets[i]), // Instant 0ms send
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLiveTouchArea() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF12122A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
      ),
      child: Row(
        children: [
          // Instant Hardware Live Touch Button with Listener (0ms delay)
          Listener(
            onPointerDown: (_) => _onLiveTouchStart(),
            onPointerUp: (_) => _onLiveTouchEnd(),
            onPointerCancel: (_) => _onLiveTouchEnd(),
            child: Column(
              children: [
                Container(
                  width: 105,
                  height: 105,
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
                    size: 42,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _isHoldingLive ? 'Yuborilmoqda...' : 'Bosib\nushlab turing',
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
          const SizedBox(width: 18),
          // Instant selection list (Tapping sends immediately)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: kBuiltinPresets.take(5).map((p) {
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
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Tarix',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                InkWell(
                  onTap: _showAllHistory,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text(
                      'Hammasini ko\'r',
                      style: TextStyle(
                        fontSize: 13,
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
              padding: const EdgeInsets.all(20),
              child: Center(
                child: Text(
                  'Tarix bo\'sh',
                  style: TextStyle(color: Colors.white.withOpacity(0.3)),
                ),
              ),
            )
          else
            ...vibe.history.take(4).map((h) => HistoryTile(history: h)),
        ],
      ),
    );
  }
}
