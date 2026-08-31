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
    type: json['type'] ?? 'vibrate',
    durationMs: json['durationMs'] ?? 200,
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
    id: json['id'] ?? '',
    name: json['name'] ?? 'Signal',
    steps: (json['steps'] as List? ?? []).map((s) => VibrationStep.fromJson(s)).toList(),
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

  Map<String, dynamic> toJson() => {
    'patternName': patternName,
    'deviceName': deviceName,
    'time': time.toIso8601String(),
    'delivered': delivered,
  };

  factory VibrationHistory.fromJson(Map<String, dynamic> json) => VibrationHistory(
    patternName: json['patternName'] ?? '',
    deviceName: json['deviceName'] ?? '',
    time: json['time'] != null ? DateTime.parse(json['time']) : DateTime.now(),
    delivered: json['delivered'] ?? true,
  );
}

// ---- Exactly 10 Built-in Presets Matching UI Design ----
final List<VibrationPattern> kBuiltinPresets = [
  VibrationPattern(
    id: 'two-short',
    name: '01 Ikki qisqa',
    icon: '• –',
    colorHex: '#3B82F6',
    steps: [
      VibrationStep(type: 'vibrate', durationMs: 120, amplitude: 220),
      VibrationStep(type: 'pause', durationMs: 80),
      VibrationStep(type: 'vibrate', durationMs: 120, amplitude: 220),
    ],
  ),
  VibrationPattern(
    id: 'three-short',
    name: '02 Uch qisqa',
    icon: '•••',
    colorHex: '#A855F7',
    steps: [
      VibrationStep(type: 'vibrate', durationMs: 100, amplitude: 200),
      VibrationStep(type: 'pause', durationMs: 60),
      VibrationStep(type: 'vibrate', durationMs: 100, amplitude: 200),
      VibrationStep(type: 'pause', durationMs: 60),
      VibrationStep(type: 'vibrate', durationMs: 100, amplitude: 200),
    ],
  ),
  VibrationPattern(
    id: 'long',
    name: '03 Uzun',
    icon: '———',
    colorHex: '#F97316',
    steps: [
      VibrationStep(type: 'vibrate', durationMs: 700, amplitude: 255),
    ],
  ),
  VibrationPattern(
    id: 'long-short',
    name: '04 Uzun + qisqa',
    icon: '— •',
    colorHex: '#22C55E',
    steps: [
      VibrationStep(type: 'vibrate', durationMs: 400, amplitude: 220),
      VibrationStep(type: 'pause', durationMs: 100),
      VibrationStep(type: 'vibrate', durationMs: 150, amplitude: 220),
    ],
  ),
  VibrationPattern(
    id: 'short-short',
    name: '05 Qisqa + qisqa',
    icon: '• •',
    colorHex: '#EAB308',
    steps: [
      VibrationStep(type: 'vibrate', durationMs: 80, amplitude: 200),
      VibrationStep(type: 'pause', durationMs: 80),
      VibrationStep(type: 'vibrate', durationMs: 80, amplitude: 200),
    ],
  ),
  VibrationPattern(
    id: 'short-long',
    name: '06 Qisqa + uzun',
    icon: '• —',
    colorHex: '#06B6D4',
    steps: [
      VibrationStep(type: 'vibrate', durationMs: 120, amplitude: 200),
      VibrationStep(type: 'pause', durationMs: 80),
      VibrationStep(type: 'vibrate', durationMs: 500, amplitude: 255),
    ],
  ),
  VibrationPattern(
    id: 'long-long',
    name: '07 Uzun + uzun',
    icon: '— —',
    colorHex: '#EF4444',
    steps: [
      VibrationStep(type: 'vibrate', durationMs: 450, amplitude: 240),
      VibrationStep(type: 'pause', durationMs: 120),
      VibrationStep(type: 'vibrate', durationMs: 450, amplitude: 240),
    ],
  ),
  VibrationPattern(
    id: 'three-short-long',
    name: '08 Uch qisqa + uzun',
    icon: '••• —',
    colorHex: '#EC4899',
    steps: [
      VibrationStep(type: 'vibrate', durationMs: 80, amplitude: 200),
      VibrationStep(type: 'pause', durationMs: 50),
      VibrationStep(type: 'vibrate', durationMs: 80, amplitude: 200),
      VibrationStep(type: 'pause', durationMs: 50),
      VibrationStep(type: 'vibrate', durationMs: 80, amplitude: 200),
      VibrationStep(type: 'pause', durationMs: 100),
      VibrationStep(type: 'vibrate', durationMs: 400, amplitude: 255),
    ],
  ),
  VibrationPattern(
    id: 'short-series',
    name: '09 Qisqa (seriya)',
    icon: '••••',
    colorHex: '#6366F1',
    steps: [
      for (int i = 0; i < 6; i++) ...[
        VibrationStep(type: 'vibrate', durationMs: 60, amplitude: 220),
        VibrationStep(type: 'pause', durationMs: 50),
      ]
    ],
  ),
  VibrationPattern(
    id: 'long-series',
    name: '10 Uzun (seriya)',
    icon: '—— —',
    colorHex: '#F59E0B',
    steps: [
      VibrationStep(type: 'vibrate', durationMs: 300, amplitude: 250),
      VibrationStep(type: 'pause', durationMs: 100),
      VibrationStep(type: 'vibrate', durationMs: 300, amplitude: 250),
      VibrationStep(type: 'pause', durationMs: 100),
      VibrationStep(type: 'vibrate', durationMs: 500, amplitude: 255),
    ],
  ),
];
