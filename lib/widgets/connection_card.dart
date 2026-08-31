import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/device_service.dart';
import '../services/peer_service.dart';

class ConnectionCard extends StatelessWidget {
  const ConnectionCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<DeviceService, PeerService>(
      builder: (context, ds, ps, _) {
        final active = ds.activeDevice;
        final isConnectedToServer = ps.isConnected;
        final isPeerOnline = ps.isPeerOnline;

        Color statusColor;
        String titleText;
        String subtitleText;

        if (active == null) {
          statusColor = Colors.white30;
          titleText = "Qurilma ulanmagan";
          subtitleText = "Juftlash uchun 'Устройства' bo'limiga o'ting";
        } else if (!isConnectedToServer) {
          statusColor = const Color(0xFFF59E0B);
          titleText = "Serverga ulanmoqda...";
          subtitleText = active.name;
        } else if (isPeerOnline) {
          statusColor = const Color(0xFF22C55E); // Green
          titleText = "Ulanish o'rnatildi (Onlayn)";
          subtitleText = active.name;
        } else {
          statusColor = Colors.white54; // Offline
          titleText = "Qurilma oflayn";
          subtitleText = "${active.name} (Internet kutilyapti)";
        }

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF12122A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: statusColor.withOpacity(0.3),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: statusColor,
                  boxShadow: [
                    BoxShadow(
                      color: statusColor.withOpacity(0.6),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titleText,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitleText,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
              // Signal indicator bars
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(4, (i) {
                  final activeBars = isPeerOnline ? 4 : (isConnectedToServer ? 2 : 1);
                  final isBarActive = i < activeBars;
                  return Container(
                    width: 3.5,
                    height: 6.0 + (i * 4.0),
                    margin: const EdgeInsets.only(left: 3),
                    decoration: BoxDecoration(
                      color: isBarActive ? statusColor : Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  );
                }),
              ),
            ],
          ),
        );
      },
    );
  }
}
