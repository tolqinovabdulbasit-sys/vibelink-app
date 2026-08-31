import 'package:flutter/material.dart';

class AckStrip extends StatelessWidget {
  final List<String> states;
  const AckStrip({super.key, required this.states});

  @override
  Widget build(BuildContext context) {
    final allIdle = states.every((s) => s == 'idle');
    if (allIdle) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF12122A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _AckStep(icon: '📤', label: 'Yuborildi', state: states[0]),
          _arrow(),
          _AckStep(icon: '☁️', label: 'Server', state: states[1]),
          _arrow(),
          _AckStep(icon: '📱', label: 'Qabul', state: states[2]),
          _arrow(),
          _AckStep(icon: '✅', label: 'Bajarildi', state: states[3]),
        ],
      ),
    );
  }

  Widget _arrow() => Text('›', style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 18));
}

class _AckStep extends StatelessWidget {
  final String icon;
  final String label;
  final String state;
  const _AckStep({required this.icon, required this.label, required this.state});

  @override
  Widget build(BuildContext context) {
    final isDone = state == 'done';
    final isLoading = state == 'loading';
    return Column(
      children: [
        if (isLoading)
          const SizedBox(width: 20, height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6C63FF)))
        else
          Text(icon, style: TextStyle(fontSize: 18, opacity: isDone ? 1.0 : 0.3)),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 9, color: isDone ? const Color(0xFF6C63FF) : Colors.white.withOpacity(0.3))),
      ],
    );
  }
}

extension on Text {
  Text withOpacity(double opacity) => Text(data ?? '', style: style?.copyWith(color: style?.color?.withOpacity(opacity)));
}
