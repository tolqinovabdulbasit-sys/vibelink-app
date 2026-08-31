import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';
import '../models/vibration_pattern.dart';

class VibrationService extends ChangeNotifier {
  static const _nativeChannel = MethodChannel('com.vibelink.app/foreground_service');

  bool _isVibrating = false;
  Timer? _liveTimer;
  VibrationPattern? _currentPattern;
  final List<VibrationHistory> _history = [];
  final List<VibrationPattern> _customPatterns = [];

  bool get isVibrating => _isVibrating;
  List<VibrationHistory> get history => List.unmodifiable(_history);
  List<VibrationPattern> get customPatterns => List.unmodifiable(_customPatterns);
  VibrationPattern? get currentPattern => _currentPattern;

  VibrationService() {
    _init();
  }

  Future<void> _init() async {
    await _loadHistory();
    await _loadCustomPatterns();
    // Ensure native foreground service is active
    try {
      await _nativeChannel.invokeMethod('startService');
    } catch (_) {}
  }

  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('vibration_history') ?? '[]';
      final list = jsonDecode(raw) as List;
      _history.clear();
      _history.addAll(list.map((e) => VibrationHistory.fromJson(e)).toList());
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading history: $e');
    }
  }

  Future<void> _saveHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(_history.map((e) => e.toJson()).toList());
      await prefs.setString('vibration_history', encoded);
    } catch (e) {
      debugPrint('Error saving history: $e');
    }
  }

  Future<void> _loadCustomPatterns() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('custom_vibration_patterns') ?? '[]';
      final list = jsonDecode(raw) as List;
      _customPatterns.clear();
      _customPatterns.addAll(list.map((e) => VibrationPattern.fromJson(e)).toList());
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading custom patterns: $e');
    }
  }

  Future<void> _saveCustomPatterns() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(_customPatterns.map((e) => e.toJson()).toList());
      await prefs.setString('custom_vibration_patterns', encoded);
    } catch (e) {
      debugPrint('Error saving custom patterns: $e');
    }
  }

  Future<void> saveCustomPattern(VibrationPattern pattern) async {
    _customPatterns.removeWhere((p) => p.id == pattern.id);
    _customPatterns.insert(0, pattern);
    await _saveCustomPatterns();
    notifyListeners();
  }

  Future<void> deleteCustomPattern(String id) async {
    _customPatterns.removeWhere((p) => p.id == id);
    await _saveCustomPatterns();
    notifyListeners();
  }

  Future<void> clearHistory() async {
    _history.clear();
    await _saveHistory();
    notifyListeners();
  }

  Future<bool> hasVibrator() async {
    final hasVib = await Vibration.hasVibrator();
    return hasVib ?? false;
  }

  Future<void> playPatternLocally(VibrationPattern pattern) async {
    await playPattern(pattern, deviceName: 'Lokal Sinov');
  }

  Future<void> playPattern(VibrationPattern pattern, {String deviceName = ''}) async {
    try { await Vibration.cancel(); } catch (_) {}
    _isVibrating = true;
    _currentPattern = pattern;
    notifyListeners();

    try {
      List<int> vib = [0];
      List<int> amp = [0];
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
      debugPrint('Vibration plugin error: $e');
      // Hardware fallback: trigger native vibrator via Foreground Service
      try {
        int total = pattern.steps.fold(0, (sum, s) => sum + (s.type == 'vibrate' ? s.durationMs : 0));
        await _nativeChannel.invokeMethod('vibrateDirect', {
          'duration': total > 0 ? total : 400,
          'amplitude': 255,
        });
      } catch (_) {}
    }

    int totalDuration = pattern.steps.fold(0, (sum, s) => sum + s.durationMs);
    Timer(Duration(milliseconds: totalDuration + 50), () {
      _isVibrating = false;
      notifyListeners();
    });

    _history.insert(0, VibrationHistory(
      patternName: pattern.name,
      deviceName: deviceName.isEmpty ? 'Sherik' : deviceName,
      time: DateTime.now(),
      delivered: true,
    ));
    if (_history.length > 50) _history.removeLast();
    _saveHistory();
    notifyListeners();
  }

  void startLive() {
    if (_isVibrating) return;
    _isVibrating = true;
    notifyListeners();
    try {
      Vibration.vibrate(duration: 500, amplitude: 255);
    } catch (_) {
      _nativeChannel.invokeMethod('vibrateDirect', {'duration': 500, 'amplitude': 255});
    }
    _liveTimer?.cancel();
    _liveTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      try {
        Vibration.vibrate(duration: 350, amplitude: 255);
      } catch (_) {
        _nativeChannel.invokeMethod('vibrateDirect', {'duration': 350, 'amplitude': 255});
      }
    });
  }

  void stopLive() {
    _liveTimer?.cancel();
    _liveTimer = null;
    try { Vibration.cancel(); } catch (_) {}
    _isVibrating = false;
    notifyListeners();
  }

  Future<void> stop() async {
    _liveTimer?.cancel();
    _liveTimer = null;
    try { await Vibration.cancel(); } catch (_) {}
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
    _saveHistory();
    notifyListeners();
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    super.dispose();
  }
}
