import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/vibration_pattern.dart';
import '../services/vibration_service.dart';
import '../services/peer_service.dart';
import '../services/device_service.dart';

class StudioScreen extends StatefulWidget {
  const StudioScreen({super.key});

  @override
  State<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends State<StudioScreen> {
  final _nameCtrl = TextEditingController(text: 'Mening Patternim');
  
  // 4 Simple Controls:
  int _durationMs = 250; // 50ms to 2000ms
  int _pauseMs = 120; // 50ms to 1000ms
  int _intensityPercent = 80; // 10% to 100%
  int _pulseCount = 2; // 1 to 5 pulses

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  VibrationPattern _buildCurrentPattern() {
    final amplitude = ((_intensityPercent / 100.0) * 255).round().clamp(10, 255);
    final steps = <VibrationStep>[];

    for (int i = 0; i < _pulseCount; i++) {
      steps.add(VibrationStep(
        durationMs: _durationMs,
        amplitude: amplitude,
        type: 'vibrate',
      ));
      if (i < _pulseCount - 1) {
        steps.add(VibrationStep(
          durationMs: _pauseMs,
          amplitude: 0,
          type: 'pause',
        ));
      }
    }

    final name = _nameCtrl.text.trim().isEmpty ? 'Mening Patternim' : _nameCtrl.text.trim();
    final desc = _pulseCount > 1 
        ? 'Davomiylik: ${_durationMs}ms, Pauza: ${_pauseMs}ms, Kuch: $_intensityPercent%, Puls: $_pulseCount'
        : 'Davomiylik: ${_durationMs}ms, Kuch: $_intensityPercent%, Puls: 1';
    return VibrationPattern(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      description: desc,
      icon: '⚡',
      colorHex: '#6C63FF',
      steps: steps,
    );
  }

  void _testPatternLocally() {
    final pattern = _buildCurrentPattern();
    final vibeService = context.read<VibrationService>();
    vibeService.playPatternLocally(pattern);
    _showSnack('Vibratsiya sinovdan o\'tkazildi');
  }

  void _savePattern() {
    final pattern = _buildCurrentPattern();
    final vibeService = context.read<VibrationService>();
    vibeService.saveCustomPattern(pattern);
    _showSnack('Pattern saqlandi: ${pattern.name}');
  }

  void _sendPatternToPeer(VibrationPattern pattern) {
    final ps = context.read<PeerService>();
    final ds = context.read<DeviceService>();
    final active = ds.activeDevice;

    if (active == null || !ps.isConnected) {
      _showSnack('Xato: Sherik telefon ulanmagan!');
      return;
    }

    ps.sendPattern(pattern, active.id);
    _showSnack('${pattern.name} sherikka yuborildi!');
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFF6C63FF),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pattern = _buildCurrentPattern();

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Pattern Studio', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Waveform Preview Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [const Color(0xFF12122A), const Color(0xFF1E1E3F)],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(pattern.name, style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white, fontSize: 16)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6C63FF).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${pattern.totalDurationMs} ms',
                          style: const TextStyle(color: Color(0xFF6C63FF), fontWeight: FontWeight.w700, fontSize: 12, fontFamily: 'JetBrains Mono'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 60,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: _SimpleWaveformPainter(pattern.steps),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 3 Simple Controls Section
            const Text('Vibratsiya Sozlamalari', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF12122A),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Column(
                children: [
                  // Slider 1: Davomiylik
                  _StudioSliderRow(
                    label: '1. Davomiylik (har bir puls)',
                    valueText: '${_durationMs} ms',
                    val: _durationMs.toDouble(),
                    min: 50,
                    max: 2000,
                    divisions: 39,
                    onChanged: (v) => setState(() => _durationMs = v.round()),
                  ),
                  const Divider(color: Colors.white10, height: 24),

                  // Slider 2: Kuch
                  _StudioSliderRow(
                    label: '2. Vibratsiya kuchi',
                    valueText: '$_intensityPercent %',
                    val: _intensityPercent.toDouble(),
                    min: 10,
                    max: 100,
                    divisions: 18,
                    onChanged: (v) => setState(() => _intensityPercent = v.round()),
                  ),
                  const Divider(color: Colors.white10, height: 24),

                  // Slider 3: Puls soni
                  _StudioSliderRow(
                    label: '3. Puls (takrorlanish) soni',
                    valueText: '$_pulseCount marta',
                    val: _pulseCount.toDouble(),
                    min: 1,
                    max: 5,
                    divisions: 4,
                    onChanged: (v) => setState(() => _pulseCount = v.round()),
                  ),

                  // Slider 4: Pulslar orasidagi pauza (faqat 2+ puls bo'lganda)
                  if (_pulseCount > 1) ...[
                    const Divider(color: Colors.white10, height: 24),
                    _StudioSliderRow(
                      label: '4. Pulslar orasidagi pauza',
                      valueText: '${_pauseMs} ms',
                      val: _pauseMs.toDouble(),
                      min: 50,
                      max: 1000,
                      divisions: 19,
                      onChanged: (v) => setState(() => _pauseMs = v.round()),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Pattern Name & Action Buttons
            const Text('Saqlash va Sinash', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
            const SizedBox(height: 10),
            TextField(
              controller: _nameCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Pattern nomi (masalan: Mening Signalim)...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                filled: true,
                fillColor: const Color(0xFF12122A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _testPatternLocally,
                    icon: const Icon(Icons.vibration_rounded),
                    label: const Text('Sinab ko\'rish'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF00D4FF),
                      side: const BorderSide(color: Color(0xFF00D4FF)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _savePattern,
                    icon: const Icon(Icons.save_rounded),
                    label: const Text('Saqlash'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C63FF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Saved Patterns Section
            Consumer<VibrationService>(
              builder: (ctx, vibe, _) {
                if (vibe.customPatterns.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Saqlangan Patternlar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                    const SizedBox(height: 10),
                    ...vibe.customPatterns.map((p) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF12122A),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.graphic_eq_rounded, color: Color(0xFF6C63FF), size: 22),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white, fontSize: 13)),
                                Text(p.description, style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.4))),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => _sendPatternToPeer(p),
                            icon: const Icon(Icons.send_rounded, color: Color(0xFF22C55E), size: 20),
                          ),
                          IconButton(
                            onPressed: () => vibe.deleteCustomPattern(p.id),
                            icon: Icon(Icons.delete_outline_rounded, color: Colors.red.withOpacity(0.7), size: 20),
                          ),
                        ],
                      ),
                    )),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _StudioSliderRow extends StatelessWidget {
  final String label;
  final String valueText;
  final double val, min, max;
  final int divisions;
  final ValueChanged<double> onChanged;

  const _StudioSliderRow({
    required this.label,
    required this.valueText,
    required this.val,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.85))),
            Text(valueText, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF6C63FF), fontFamily: 'JetBrains Mono')),
          ],
        ),
        const SizedBox(height: 6),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
            activeTrackColor: const Color(0xFF6C63FF),
            inactiveTrackColor: Colors.white.withOpacity(0.1),
            thumbColor: const Color(0xFF6C63FF),
            overlayColor: const Color(0xFF6C63FF).withOpacity(0.2),
          ),
          child: Slider(
            value: val,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _SimpleWaveformPainter extends CustomPainter {
  final List<VibrationStep> steps;
  _SimpleWaveformPainter(this.steps);

  @override
  void paint(Canvas canvas, Size size) {
    if (steps.isEmpty) return;

    final totalMs = steps.fold(0, (s, e) => s + e.durationMs).toDouble();
    if (totalMs <= 0) return;

    double x = 12;
    final maxW = size.width - 24;
    final centerY = size.height / 2;
    final paint = Paint()..strokeCap = StrokeCap.round..strokeWidth = 4;

    for (final step in steps) {
      final w = (step.durationMs / totalMs) * maxW;
      if (step.type == 'vibrate') {
        final h = (step.amplitude / 255.0) * (centerY - 6);
        paint.color = const Color(0xFF6C63FF);
        canvas.drawLine(Offset(x, centerY - h), Offset(x + w, centerY - h), paint);
        canvas.drawLine(Offset(x, centerY + h), Offset(x + w, centerY + h), paint);
        canvas.drawLine(Offset(x, centerY - h), Offset(x, centerY + h), paint..strokeWidth = 2);
        canvas.drawLine(Offset(x + w, centerY - h), Offset(x + w, centerY + h), paint..strokeWidth = 2);
        paint.strokeWidth = 4;
      } else {
        paint.color = Colors.white.withOpacity(0.2);
        canvas.drawLine(Offset(x, centerY), Offset(x + w, centerY), paint..strokeWidth = 2);
        paint.strokeWidth = 4;
      }
      x += w;
    }
  }

  @override
  bool shouldRepaint(covariant _SimpleWaveformPainter old) => old.steps != steps;
}
