import 'package:flutter/material.dart';
import '../models/vibration_pattern.dart';

class PresetCard extends StatelessWidget {
  final VibrationPattern pattern;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onSend;

  const PresetCard({super.key, required this.pattern, required this.isSelected, required this.onTap, required this.onSend});

  @override
  Widget build(BuildContext context) {
    final color = Color(int.parse(pattern.colorHex.replaceFirst('#', '0xFF')));
    return GestureDetector(
      onTap: onTap,
      onDoubleTap: onSend,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 90,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.2) : const Color(0xFF12122A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color.withOpacity(0.6) : Colors.white.withOpacity(0.06),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(pattern.icon, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 6),
            Text(pattern.name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
            Text(pattern.steps.length > 1 ? '${pattern.steps.length} qadam' : '1 qadam',
              style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.4))),
          ],
        ),
      ),
    );
  }
}
