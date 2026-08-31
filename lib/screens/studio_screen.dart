import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/vibration_pattern.dart';
import '../services/vibration_service.dart';
import '../services/device_service.dart';
import '../services/peer_service.dart';

class StudioScreen extends StatefulWidget {
  const StudioScreen({super.key});
  @override
  State<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends State<StudioScreen> {
  List<VibrationStep> _steps = [];
  double _amplitude = 50;
  int _durationMs = 200;
  int _pauseMs = 100;
  final _nameCtrl = TextEditingController();
  List<VibrationPattern> _saved = [];

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('custom_patterns') ?? '[]';
    final list = jsonDecode(raw) as List;
    setState(() => _saved = list.map((e) => VibrationPattern.fromJson(e)).toList());
  }

  Future<void> _saveCurrent() async {
    if (_steps.isEmpty) {
      _showSnack('Kamida bitta qadam qo\'shing');
      return;
    }
    final name = _nameCtrl.text.trim().isEmpty ? 'Pattern ${_saved.length + 1}' : _nameCtrl.text.trim();
    final pattern = VibrationPattern(
      id: const Uuid().v4(),
      name: name,
      steps: List.from(_steps),
      colorHex: '#6C63FF',
    );
    _saved.insert(0, pattern);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('custom_patterns', jsonEncode(_saved.map((p) => p.toJson()).toList()));
    setState(() {});
    _showSnack('Saqlandi: $name');
  }

  Future<void> _testPattern() async {
    if (_steps.isEmpty) { _showSnack('Avval pattern yarating'); return; }
    final pattern = VibrationPattern(id: 'test', name: 'Test', steps: _steps);
    await context.read<VibrationService>().playPattern(pattern);
    _showSnack('Tebranish bajarildi!');
  }

  Future<void> _sendSaved(VibrationPattern pattern) async {
    final ds = context.read<DeviceService>();
    final ps = context.read<PeerService>();
    final active = ds.activeDevice;
    if (active == null) { _showSnack('Qurilma tanlanmagan'); return; }
    ps.sendPattern(pattern, active.id);
    _showSnack('Yuborildi!');
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: const Color(0xFF6C63FF), behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
  }

  Future<void> _deleteSaved(String id) async {
    _saved.removeWhere((p) => p.id == id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('custom_patterns', jsonEncode(_saved.map((p) => p.toJson()).toList()));
    setState(() {});
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(child: Text('Pattern Studio',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white))),
            const SizedBox(height: 20),
            _buildWaveformVisual(),
            const SizedBox(height: 16),
            _buildStepsButtons(),
            const SizedBox(height: 16),
            _buildStepsList(),
            const SizedBox(height: 20),
            _buildSliders(),
            const SizedBox(height: 20),
            _buildActions(),
            const SizedBox(height: 24),
            const Text('Saqlangan Patternlar',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
            const SizedBox(height: 12),
            if (_saved.isEmpty)
              Center(child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text("Hali pattern yo'q", style: TextStyle(color: Colors.white.withOpacity(0.3))),
              ))
            else
              ..._saved.map((p) => _SavedPatternTile(
                pattern: p,
                onSend: () => _sendSaved(p),
                onDelete: () => _deleteSaved(p.id),
              )),
          ],
        ),
      ),
    );
  }

  Widget _buildWaveformVisual() {
    return Container(
      width: double.infinity,
      height: 100,
      decoration: BoxDecoration(
        color: const Color(0xFF12122A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: _steps.isEmpty
          ? Center(child: Text("Tebranish yoki pauza qo'shing",
              style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12)))
          : CustomPaint(painter: _WaveformPainter(_steps), size: Size.infinite),
    );
  }

  Widget _buildStepsButtons() {
    return Row(
      children: [
        Expanded(child: _ActionBtn(
          label: '+ Tebranish',
          color: const Color(0xFF6C63FF),
          onTap: () => setState(() => _steps.add(VibrationStep(
            type: 'vibrate', durationMs: _durationMs, amplitude: (_amplitude * 2.55).round()))),
        )),
        const SizedBox(width: 10),
        Expanded(child: _ActionBtn(
          label: '+ Pauza',
          color: const Color(0xFF334155),
          onTap: () => setState(() => _steps.add(VibrationStep(type: 'pause', durationMs: _pauseMs))),
        )),
        const SizedBox(width: 10),
        _ActionBtn(
          label: 'Tozala',
          color: const Color(0xFFEF4444).withOpacity(0.15),
          textColor: const Color(0xFFEF4444),
          onTap: () => setState(() => _steps.clear()),
        ),
      ],
    );
  }

  Widget _buildStepsList() {
    if (_steps.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF12122A),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Wrap(
        spacing: 6, runSpacing: 6,
        children: _steps.asMap().entries.map((e) {
          final s = e.value;
          final isVibe = s.type == 'vibrate';
          return GestureDetector(
            onTap: () => setState(() => _steps.removeAt(e.key)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isVibe ? const Color(0xFF6C63FF).withOpacity(0.2) : Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isVibe ? const Color(0xFF6C63FF).withOpacity(0.4) : Colors.white.withOpacity(0.1)),
              ),
              child: Text(
                isVibe ? '▶ ${s.durationMs}ms' : '⏸ ${s.durationMs}ms',
                style: TextStyle(fontSize: 11, fontFamily: 'JetBrains Mono',
                  color: isVibe ? const Color(0xFF6C63FF) : Colors.white.withOpacity(0.5)),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSliders() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF12122A), borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          _SliderRow(label: 'Kuch', value: _amplitude.round(), suffix: '%',
            min: 1, max: 100, val: _amplitude,
            onChanged: (v) => setState(() => _amplitude = v)),
          _SliderRow(label: 'Davomiylik', value: _durationMs, suffix: 'ms',
            min: 50, max: 1000, val: _durationMs.toDouble(),
            onChanged: (v) => setState(() => _durationMs = v.round())),
          _SliderRow(label: 'Pauza', value: _pauseMs, suffix: 'ms',
            min: 0, max: 500, val: _pauseMs.toDouble(),
            onChanged: (v) => setState(() => _pauseMs = v.round()), isLast: true),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Column(
      children: [
        TextField(
          controller: _nameCtrl,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Pattern nomi...',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
            filled: true, fillColor: const Color(0xFF12122A),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: _testPattern,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Sinovdan o\'tkaz'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF6C63FF),
                side: const BorderSide(color: Color(0xFF6C63FF)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            )),
            const SizedBox(width: 12),
            Expanded(child: ElevatedButton.icon(
              onPressed: _saveCurrent,
              icon: const Icon(Icons.save_rounded),
              label: const Text('Saqlash'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C63FF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            )),
          ],
        ),
      ],
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final Color color;
  final Color? textColor;
  final VoidCallback onTap;
  const _ActionBtn({required this.label, required this.color, required this.onTap, this.textColor});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
      child: Text(label, textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textColor ?? Colors.white)),
    ),
  );
}

class _SliderRow extends StatelessWidget {
  final String label;
  final int value;
  final String suffix;
  final double min, max, val;
  final ValueChanged<double> onChanged;
  final bool isLast;
  const _SliderRow({required this.label, required this.value, required this.suffix,
    required this.min, required this.max, required this.val, required this.onChanged, this.isLast = false});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.7))),
          Text('$value$suffix', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF6C63FF), fontFamily: 'JetBrains Mono')),
        ],
      ),
      SliderTheme(
        data: SliderThemeData(
          trackHeight: 3,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
          activeTrackColor: const Color(0xFF6C63FF),
          inactiveTrackColor: Colors.white.withOpacity(0.1),
          thumbColor: const Color(0xFF6C63FF),
          overlayColor: const Color(0xFF6C63FF).withOpacity(0.2),
        ),
        child: Slider(value: val, min: min, max: max, onChanged: onChanged),
      ),
      if (!isLast) Divider(color: Colors.white.withOpacity(0.06), height: 1),
    ],
  );
}

class _SavedPatternTile extends StatelessWidget {
  final VibrationPattern pattern;
  final VoidCallback onSend;
  final VoidCallback onDelete;
  const _SavedPatternTile({required this.pattern, required this.onSend, required this.onDelete});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: const Color(0xFF12122A),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white.withOpacity(0.06)),
    ),
    child: Row(
      children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF6C63FF).withOpacity(0.15),
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.graphic_eq_rounded, color: Color(0xFF6C63FF), size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(pattern.name, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
            Text('${pattern.steps.length} qadam', style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.4))),
          ],
        )),
        IconButton(onPressed: onSend, icon: const Icon(Icons.send_rounded, color: Color(0xFF6C63FF), size: 20)),
        IconButton(onPressed: onDelete, icon: Icon(Icons.delete_outline_rounded, color: const Color(0xFFEF4444).withOpacity(0.7), size: 20)),
      ],
    ),
  );
}

class _WaveformPainter extends CustomPainter {
  final List<VibrationStep> steps;
  _WaveformPainter(this.steps);

  @override
  void paint(Canvas canvas, Size size) {
    final total = steps.fold(0, (s, e) => s + e.durationMs).toDouble();
    if (total == 0) return;
    double x = 16;
    final maxW = size.width - 32;
    final centerY = size.height / 2;
    final paint = Paint()..strokeCap = StrokeCap.round..strokeWidth = 4;
    for (final step in steps) {
      final w = (step.durationMs / total) * maxW;
      if (step.type == 'vibrate') {
        final h = (step.amplitude / 255.0) * (centerY - 8);
        paint.color = const Color(0xFF6C63FF);
        canvas.drawLine(Offset(x, centerY - h), Offset(x + w, centerY - h), paint);
        canvas.drawLine(Offset(x, centerY + h), Offset(x + w, centerY + h), paint);
        canvas.drawLine(Offset(x, centerY - h), Offset(x, centerY + h), paint..strokeWidth = 2);
        canvas.drawLine(Offset(x + w, centerY - h), Offset(x + w, centerY + h), paint..strokeWidth = 2);
        paint.strokeWidth = 4;
      } else {
        paint.color = Colors.white.withOpacity(0.15);
        canvas.drawLine(Offset(x, centerY), Offset(x + w, centerY), paint..strokeWidth = 2);
        paint.strokeWidth = 4;
      }
      x += w;
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) => old.steps != steps;
}
