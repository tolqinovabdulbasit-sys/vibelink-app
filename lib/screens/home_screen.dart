import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
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

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  VibrationPattern? _selectedPreset;
  bool _liveHolding = false;
  final List<String> _ackStates = ['idle', 'idle', 'idle', 'idle'];
  Timer? _ackTimer;

  @override
  void initState() {
    super.initState();
    _selectedPreset = kBuiltinPresets.first;
    final peerService = context.read<PeerService>();
    peerService.onVibeReceived = _onVibeReceived;
    peerService.onLiveStart = _onLiveStart;
    peerService.onLiveStop = _onLiveStop;
    peerService.onAckReceived = _onAck;
    peerService.onError = _onError;
  }

  void _onVibeReceived(VibrationPattern pattern) {
    context.read<VibrationService>().playPattern(pattern, deviceName: 'Sherik');
  }

  void _onLiveStart() => context.read<VibrationService>().startLive();
  void _onLiveStop() => context.read<VibrationService>().stopLive();

  void _onAck(String id) {
    if (!mounted) return;
    if (id.startsWith('sent:')) {
      setState(() {
        _ackStates[0] = 'done';
        _ackStates[1] = 'loading';
      });
      Future.delayed(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        setState(() {
          _ackStates[1] = 'done';
          _ackStates[2] = 'loading';
        });
      });
      Future.delayed(const Duration(milliseconds: 700), () {
        if (!mounted) return;
        setState(() {
          _ackStates[2] = 'done';
          _ackStates[3] = 'loading';
        });
      });
      Future.delayed(const Duration(milliseconds: 1100), () {
        if (!mounted) return;
        setState(() => _ackStates[3] = 'done');
        _ackTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _ackStates.fillRange(0, 4, 'idle'));
        });
      });
    }
  }

  void _onError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: const Color(0xFFEF4444)),
    );
  }

  Future<void> _sendPattern(VibrationPattern pattern) async {
    final deviceService = context.read<DeviceService>();
    final peerService = context.read<PeerService>();
    final activeDevice = deviceService.activeDevice;
    if (activeDevice == null) {
      _onError("Qurilma tanlanmagan. Avval qurilma qo'shing.");
      return;
    }
    setState(() => _ackStates.fillRange(0, 4, 'idle'));
    await peerService.sendPattern(pattern, activeDevice.id);
  }

  void _startLive() {
    final deviceService = context.read<DeviceService>();
    final peerService = context.read<PeerService>();
    final activeDevice = deviceService.activeDevice;
    if (activeDevice == null) {
      _onError("Qurilma tanlanmagan.");
      return;
    }
    setState(() => _liveHolding = true);
    context.read<VibrationService>().startLive();
    peerService.sendLiveStart(activeDevice.id);
  }

  void _stopLive() {
    final deviceService = context.read<DeviceService>();
    final peerService = context.read<PeerService>();
    final activeDevice = deviceService.activeDevice;
    setState(() => _liveHolding = false);
    context.read<VibrationService>().stopLive();
    if (activeDevice != null) peerService.sendLiveStop(activeDevice.id);
  }

  @override
  void dispose() {
    _ackTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildHeader()),
          SliverToBoxAdapter(child: ConnectionCard()),
          SliverToBoxAdapter(child: _buildPresetsSection()),
          SliverToBoxAdapter(child: _buildLiveTouchArea()),
          SliverToBoxAdapter(child: AckStrip(states: _ackStates)),
          SliverToBoxAdapter(child: _buildHistorySection()),
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Icon(Icons.menu_rounded, color: Colors.white.withOpacity(0.7), size: 24),
          const Expanded(
            child: Center(
              child: Text('VibeLink', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800,
                color: Colors.white, letterSpacing: -0.3)),
            ),
          ),
          Icon(Icons.person_rounded, color: Colors.white.withOpacity(0.7), size: 24),
        ],
      ),
    );
  }

  Widget _buildPresetsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Text('Tez Signallar', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
        ),
        SizedBox(
          height: 110,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(left: 16),
            itemCount: kBuiltinPresets.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.only(right: 10),
              child: PresetCard(
                pattern: kBuiltinPresets[i],
                isSelected: _selectedPreset?.id == kBuiltinPresets[i].id,
                onTap: () => setState(() => _selectedPreset = kBuiltinPresets[i]),
                onSend: () => _sendPattern(kBuiltinPresets[i]),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLiveTouchArea() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF12122A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.06), width: 1),
      ),
      child: Row(
        children: [
          // Live Touch Button
          Column(
            children: [
              GestureDetector(
                onTapDown: (_) => _startLive(),
                onTapUp: (_) => _stopLive(),
                onTapCancel: () => _stopLive(),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: _liveHolding
                          ? [const Color(0xFF6C63FF), const Color(0xFF4A00E0)]
                          : [const Color(0xFF2A2A4A), const Color(0xFF1A1A3A)],
                    ),
                    boxShadow: _liveHolding ? [
                      BoxShadow(color: const Color(0xFF6C63FF).withOpacity(0.5), blurRadius: 24, spreadRadius: 4),
                    ] : [],
                  ),
                  child: Icon(Icons.touch_app_rounded, color: _liveHolding ? Colors.white : Colors.white.withOpacity(0.5), size: 36),
                ),
              ),
              const SizedBox(height: 8),
              Text('Bosib\nushlab turing',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.5))),
            ],
          ),
          const SizedBox(width: 20),
          // Quick options
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: kBuiltinPresets.take(5).map((p) => GestureDetector(
                onTap: () { _selectedPreset = p; _sendPattern(p); },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 8, height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(int.parse(p.colorHex.replaceFirst('#', '0xFF'))),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(p.name, style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.7))),
                    ],
                  ),
                ),
              )).toList(),
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
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Tarix', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
                Text('Hammasini ko\'r', style: TextStyle(fontSize: 13, color: const Color(0xFF6C63FF))),
              ],
            ),
          ),
          if (vibe.history.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(child: Text('Tarix bo\'sh', style: TextStyle(color: Colors.white.withOpacity(0.3)))),
            )
          else
            ...vibe.history.take(5).map((h) => HistoryTile(history: h)),
        ],
      ),
    );
  }
}
