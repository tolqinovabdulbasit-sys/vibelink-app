import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/vibration_pattern.dart';

class HistoryTile extends StatelessWidget {
  final VibrationHistory history;
  const HistoryTile({super.key, required this.history});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF12122A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.04)),
      ),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: history.delivered ? const Color(0xFF22C55E).withOpacity(0.15) : const Color(0xFFEF4444).withOpacity(0.15),
            ),
            child: Icon(
              history.delivered ? Icons.check_rounded : Icons.close_rounded,
              color: history.delivered ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(history.patternName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.white)),
                Text(history.deviceName, style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.4))),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(DateFormat('HH:mm:ss').format(history.time),
                style: TextStyle(fontSize: 11, fontFamily: 'JetBrains Mono', color: Colors.white.withOpacity(0.4))),
              Text(history.delivered ? 'Yetkazildi' : 'Xato',
                style: TextStyle(fontSize: 10, color: history.delivered ? const Color(0xFF22C55E) : const Color(0xFFEF4444))),
            ],
          ),
        ],
      ),
    );
  }
}
