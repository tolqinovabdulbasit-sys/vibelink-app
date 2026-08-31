import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/device_service.dart';
import '../services/peer_service.dart';

class ConnectionCard extends StatelessWidget {
  const ConnectionCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<DeviceService, PeerService>(
      builder: (_, ds, ps, __) {
        final active = ds.activeDevice;
        final isOnline = ps.isConnected;
        final statusColor = active == null ? Colors.white.withOpacity(0.3)
            : active.status == 'online' ? const Color(0xFF22C55E)
            : active.status == 'connecting' ? const Color(0xFFF59E0B)
            : Colors.white.withOpacity(0.3);
        final statusText = active == null ? "Qurilma tanlanmagan"
            : active.status == 'online' ? active.name
            : "${active.name} — Oflayn";

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF12122A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: statusColor.withOpacity(0.15), width: 1),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 10, height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: statusColor,
                  boxShadow: [BoxShadow(color: statusColor.withOpacity(0.5), blurRadius: 6)],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(active == null ? 'Ulanish yo\'q' : 'Ulanish o\'rnatildi',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.white)),
                    Text(statusText, style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.5))),
                  ],
                ),
              ),
              // Signal bars
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(4, (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 4,
                  height: (i + 1) * 5.0,
                  margin: const EdgeInsets.only(left: 3),
                  decoration: BoxDecoration(
                    color: isOnline && active != null ? statusColor : Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                )),
              ),
            ],
          ),
        );
      },
    );
  }
}
