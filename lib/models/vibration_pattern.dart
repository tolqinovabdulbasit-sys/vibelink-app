class VibrationStep {
  final String type; // 'vibrate' | 'pause'
  final int durationMs;
  final int amplitude; // 1-255

  VibrationStep({
    required this.type,
    required this.durationMs,
    this.amplitude = 128,
  });

  Map<String, dynamic> toJson() => {
    'type': type,
    'durationMs': durationMs,
    'amplitude': amplitude,
  };

  factory VibrationStep.fromJson(Map<String, dynamic> json) => VibrationStep(
    type: json['type'],
    durationMs: json['durationMs'],
    amplitude: json['amplitude'] ?? 128,
  );
}

class VibrationPattern {
  final String id;
  String name;
  final List<VibrationStep> steps;
  final String colorHex;
  final String icon;

  VibrationPattern({
    required this.id,
    required this.name,
    required this.steps,
    this.colorHex = '#6C63FF',
    this.icon = '📳',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'steps': steps.map((s) => s.toJson()).toList(),
    'colorHex': colorHex,
    'icon': icon,
  };

  factory VibrationPattern.fromJson(Map<String, dynamic> json) => VibrationPattern(
    id: json['id'],
    name: json['name'],
    steps: (json['steps'] as List).map((s) => VibrationStep.fromJson(s)).toList(),
    colorHex: json['colorHex'] ?? '#6C63FF',
    icon: json['icon'] ?? '📳',
  );
}

class VibrationHistory {
  final String patternName;
  final String deviceName;
  final DateTime time;
  final bool delivered;

  VibrationHistory({
    required this.patternName,
    required this.deviceName,
    required this.time,
    required this.delivered,
  });
}

// ---- Built-in Presets ----
final List<VibrationPattern> kBuiltinPresets = [
  VibrationPattern(
    id: 'two-short',
    name: 'Signal 1',
    icon: '•–',
    colorHex: '#6C63FF',
    steps: [
      VibrationStep(type: 'vibrate', durationMs: 150, amplitude: 200),
      VibrationStep(type: 'pause', durationMs: 100),
      VibrationStep(type: 'vibrate', durationMs: 300, amplitude: 200),
    ],
  ),
  VibrationPattern(
    id: 'three-short',
    name: 'Signal 2',
    icon: '•••',
    colorHex: '#A855F7',
    steps: [
      VibrationStep(type: 'vibrate', durationMs: 120, amplitude: 180),
      VibrationStep(type: 'pause', durationMs: 80),
      VibrationStep(type: 'vibrate', durationMs: 120, amplitude: 180),
      VibrationStep(type: 'pause', durationMs: 80),
      VibrationStep(type: 'vibrate', durationMs: 120, amplitude: 180),
    ],
  ),
  VibrationPattern(
    id: 'long',
    name: 'Signal 3',
    icon: '——',
    colorHex: '#F97316',
    steps: [
      VibrationStep(type: 'vibrate', durationMs: 800, amplitude: 220),
    ],
  ),
  VibrationPattern(
    id: 'long-short',
    name: 'Signal 4',
    icon: '–•',
    colorHex: '#22C55E',
    steps: [
      VibrationStep(type: 'vibrate', durationMs: 500, amplitude: 200),
      VibrationStep(type: 'pause', durationMs: 100),
      VibrationStep(type: 'vibrate', durationMs: 150, amplitude: 200),
    ],
  ),
  VibrationPattern(
    id: 'heartbeat',
    name: 'Yurak urishi',
    icon: '❤️',
    colorHex: '#EF4444',
    steps: [
      VibrationStep(type: 'vibrate', durationMs: 100, amplitude: 255),
      VibrationStep(type: 'pause', durationMs: 50),
      VibrationStep(type: 'vibrate', durationMs: 200, amplitude: 255),
      VibrationStep(type: 'pause', durationMs: 400),
      VibrationStep(type: 'vibrate', durationMs: 100, amplitude: 255),
      VibrationStep(type: 'pause', durationMs: 50),
      VibrationStep(type: 'vibrate', durationMs: 200, amplitude: 255),
    ],
  ),
  VibrationPattern(
    id: 'escalation',
    name: "To'lqin",
    icon: '〰️',
    colorHex: '#06B6D4',
    steps: [
      VibrationStep(type: 'vibrate', durationMs: 100, amplitude: 80),
      VibrationStep(type: 'pause', durationMs: 80),
      VibrationStep(type: 'vibrate', durationMs: 150, amplitude: 140),
      VibrationStep(type: 'pause', durationMs: 80),
      VibrationStep(type: 'vibrate', durationMs: 200, amplitude: 200),
      VibrationStep(type: 'pause', durationMs: 80),
      VibrationStep(type: 'vibrate', durationMs: 300, amplitude: 255),
    ],
  ),
  VibrationPattern(
    id: 'staccato',
    name: 'Staccato',
    icon: '⚡',
    colorHex: '#EAB308',
    steps: [
      for (int i = 0; i < 5; i++) ...[
        VibrationStep(type: 'vibrate', durationMs: 80, amplitude: 230),
        VibrationStep(type: 'pause', durationMs: 60),
      ]
    ],
  ),
  VibrationPattern(
    id: 'pulse',
    name: 'Puls',
    icon: '🔄',
    colorHex: '#EC4899',
    steps: [
      for (int i = 0; i < 3; i++) ...[
        VibrationStep(type: 'vibrate', durationMs: 200, amplitude: 200),
        VibrationStep(type: 'pause', durationMs: 200),
      ]
    ],
  ),
];
