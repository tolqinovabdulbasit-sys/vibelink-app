import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:vibration/vibration.dart';
import '../models/vibration_pattern.dart';

class VibrationService extends ChangeNotifier {
  bool _isVibrating = false;
  Timer? _liveTimer;
  VibrationPattern? _currentPattern;
  final List<VibrationHistory> _history = [];

  bool get isVibrating => _isVibrating;
  List<VibrationHistory> get history => List.unmodifiable(_history);
  VibrationPattern? get currentPattern => _currentPattern;

  Future<bool> hasVibrator() async {
    final hasVib = await Vibration.hasVibrator();
    return hasVib ?? false;
  }

  Future<void> playPattern(VibrationPattern pattern, {String deviceName = ''}) async {
    if (_isVibrating) await stop();
    _isVibrating = true;
    _currentPattern = pattern;
    notifyListeners();

    try {
      List<int> vib = [];
      List<int> amp = [];
      for (final step in pattern.steps) {
        if (step.type == 'pause') {
          vib.add(step.durationMs);
          amp.add(0);
        } else {
          vib.add(step.durationMs);
          amp.add(step.amplitude);
        }
      }
      await Vibration.vibrate(pattern: vib, intensities: amp);
    } catch (e) {
      debugPrint('Vibration error: $e');
    }

    // Calculate total duration
    int total = pattern.steps.fold(0, (sum, s) => sum + s.durationMs);
    await Future.delayed(Duration(milliseconds: total + 100));
    _isVibrating = false;
    notifyListeners();

    // Add to history
    _history.insert(0, VibrationHistory(
      patternName: pattern.name,
      deviceName: deviceName,
      time: DateTime.now(),
      delivered: true,
    ));
    if (_history.length > 50) _history.removeLast();
    notifyListeners();
  }

  void startLive() {
    if (_isVibrating) return;
    _isVibrating = true;
    notifyListeners();
    // Repeat vibration every 200ms while live
    _liveTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      Vibration.vibrate(duration: 180, amplitude: 200);
    });
  }

  void stopLive() {
    _liveTimer?.cancel();
    _liveTimer = null;
    Vibration.cancel();
    _isVibrating = false;
    notifyListeners();
  }

  Future<void> stop() async {
    _liveTimer?.cancel();
    _liveTimer = null;
    await Vibration.cancel();
    _isVibrating = false;
    notifyListeners();
  }

  void addFailedHistory(String patternName, String deviceName) {
    _history.insert(0, VibrationHistory(
      patternName: patternName,
      deviceName: deviceName,
      time: DateTime.now(),
      delivered: false,
    ));
    notifyListeners();
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    super.dispose();
  }
}
