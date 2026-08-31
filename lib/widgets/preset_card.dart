import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/vibration_pattern.dart';

class PresetCard extends StatelessWidget {
  final VibrationPattern pattern;
  final bool isSelected;
  final VoidCallback onTap;

  const PresetCard({
    super.key,
    required this.pattern,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = Color(int.parse(pattern.colorHex.replaceFirst('#', '0xFF')));
    final stepsCount = pattern.steps.where((s) => s.type == 'vibrate').length;

    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap(); // Instant 0ms trigger
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 100,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.2) : const Color(0xFF161632),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : Colors.white.withOpacity(0.08),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              pattern.icon,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: color,
                fontFamily: 'JetBrains Mono',
              ),
            ),
            const SizedBox(height: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pattern.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$stepsCount qadam',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white.withOpacity(0.45),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
