import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../services/device_service.dart';
import '../services/peer_service.dart';
import 'main_scaffold.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  double _progress = 0;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _t = Timer.periodic(const Duration(milliseconds: 25), (timer) async {
      if (!mounted) return;
      setState(() => _progress += 0.04);
      if (_progress >= 1.0) {
        timer.cancel();
        if (!mounted) return;
        final devService = context.read<DeviceService>();
        final peerService = context.read<PeerService>();
        
        await peerService.init(devService.myDeviceId);
        if (devService.activeDevice != null) {
          peerService.joinChannel(devService.activeDevice!.id);
        }

        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const MainScaffold(),
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
            transitionDuration: const Duration(milliseconds: 300),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated rings
            SizedBox(
              width: 120, height: 120,
              child: Stack(alignment: Alignment.center, children: [
                Container(
                  width: 120, height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.15), width: 1),
                  ),
                ).animate(onPlay: (c) => c.repeat()).scale(
                  begin: const Offset(0.8, 0.8), end: const Offset(1.1, 1.1),
                  duration: 2000.ms, curve: Curves.easeInOut),
                Container(
                  width: 90, height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.3), width: 1.5),
                  ),
                ).animate(onPlay: (c) => c.repeat()).scale(
                  begin: const Offset(0.9, 0.9), end: const Offset(1.05, 1.05),
                  duration: 1500.ms, curve: Curves.easeInOut),
                Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6C63FF), Color(0xFF00D4FF)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [BoxShadow(color: const Color(0xFF6C63FF).withOpacity(0.5), blurRadius: 20, spreadRadius: 2)],
                  ),
                  child: const Icon(Icons.vibration, color: Colors.white, size: 28),
                ),
              ]),
            ),
            const SizedBox(height: 32),
            const Text('VibeLink',
              style: TextStyle(fontSize: 36, fontWeight: FontWeight.w800,
                color: Colors.white, letterSpacing: -0.5)),
            const SizedBox(height: 8),
            Text('Masofaviy Vibratsiya Tizimi',
              style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.5))),
            const SizedBox(height: 48),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 60),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _progress.clamp(0, 1),
                  minHeight: 4,
                  backgroundColor: Colors.white.withOpacity(0.1),
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF6C63FF)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
