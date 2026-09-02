import 'dart:async';
import 'dart:collection';
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
  final List<VibrationPattern> _customPatterns = [];

  // Queue system for incoming signals
  final Queue<VibrationPattern> _queue = Queue();
  bool _isProcessingQueue = false;

  bool? _hasAmpControl;

  bool get isVibrating => _isVibrating;
  List<VibrationPattern> get customPatterns => List.unmodifiable(_customPatterns);
  VibrationPattern? get currentPattern => _currentPattern;

  VibrationService() {
    _init();
  }

  Future<void> _init() async {
    await _loadCustomPatterns();
    try {
      _hasAmpControl = await Vibration.hasAmplitudeControl();
    } catch (_) {
      _hasAmpControl = false;
    }
    // Ensure native foreground service is active
    try {
      await _nativeChannel.invokeMethod('startService');
    } catch (_) {}
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

  Future<bool> hasVibrator() async {
    final hasVib = await Vibration.hasVibrator();
    return hasVib ?? false;
  }

  /// Play pattern locally for testing (does not enforce 3s queue pause)
  Future<void> playPatternLocally(VibrationPattern pattern) async {
    await _executeVibration(pattern);
  }

  /// Enqueue incoming vibration pattern to prevent overlaps and enforce 3-second spacing
  void enqueuePattern(VibrationPattern pattern) {
    _queue.add(pattern);
    if (!_isProcessingQueue) {
      _processQueue();
    }
  }

  Future<void> _processQueue() async {
    if (_queue.isEmpty) {
      _isProcessingQueue = false;
      return;
    }
    _isProcessingQueue = true;

    while (_queue.isNotEmpty) {
      final pattern = _queue.removeFirst();
      await _executeVibration(pattern);

      // Enforce exactly 3 seconds interval if there are more patterns in queue
      if (_queue.isNotEmpty) {
        await Future.delayed(const Duration(seconds: 3));
      }
    }

    _isProcessingQueue = false;
  }

  /// Direct pattern execution with hybrid hardware amplitude / PWM micro-pulses
  Future<void> _executeVibration(VibrationPattern pattern) async {
    try {
      await Vibration.cancel();
    } catch (_) {}

    _isVibrating = true;
    _currentPattern = pattern;
    notifyListeners();

    final hasAmp = _hasAmpControl ?? false;

    // Build timing and intensity arrays
    // If device doesn't support hardware amplitude, use PWM micro-pulsing to modulate physical intensity
    final List<int> timings = [0];
    final List<int> intensities = [0];

    for (final step in pattern.steps) {
      if (step.type == 'pause') {
        timings.add(step.durationMs);
        intensities.add(0);
      } else {
        final duration = step.durationMs;
        final amp = step.amplitude.clamp(1, 255);

        if (hasAmp) {
          // Hardware supports real amplitude
          timings.add(duration);
          intensities.add(amp);
        } else {
          // Hardware lacks amplitude control: emulate intensity via PWM Duty Cycle
          // Higher amplitude -> longer on-time, lower amplitude -> micro-pulses with off-time
          if (amp >= 220) {
            // 100% full intensity: continuous vibration
            timings.add(duration);
            intensities.add(255);
          } else {
            // PWM slice period: 40ms
            // Calculate onMs proportional to amp (10ms to 32ms)
            final double ratio = (amp / 255.0).clamp(0.15, 0.85);
            final int onMs = (40 * ratio).round().clamp(8, 34);
            final int offMs = 40 - onMs;
            int elapsed = 0;

            while (elapsed + 40 <= duration) {
              timings.add(onMs);
              intensities.add(255);
              timings.add(offMs);
              intensities.add(0);
              elapsed += 40;
            }
            final remaining = duration - elapsed;
            if (remaining > 0) {
              final remOn = (remaining * ratio).round().clamp(5, remaining);
              timings.add(remOn);
              intensities.add(255);
              if (remaining - remOn > 0) {
                timings.add(remaining - remOn);
                intensities.add(0);
              }
            }
          }
        }
      }
    }

    try {
      if (hasAmp) {
        await Vibration.vibrate(pattern: timings, intensities: intensities);
      } else {
        await Vibration.vibrate(pattern: timings);
      }
    } catch (e) {
      debugPrint('Vibration plugin fallback: $e');
      try {
        final total = pattern.steps.fold(0, (sum, s) => sum + (s.type == 'vibrate' ? s.durationMs : 0));
        await _nativeChannel.invokeMethod('vibrateDirect', {
          'duration': total > 0 ? total : 400,
          'amplitude': pattern.steps.isNotEmpty ? pattern.steps.first.amplitude : 255,
        });
      } catch (_) {}
    }

    final totalDuration = pattern.steps.fold(0, (sum, s) => sum + s.durationMs);
    await Future.delayed(Duration(milliseconds: totalDuration + 50));

    _isVibrating = false;
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
    try {
      Vibration.cancel();
    } catch (_) {}
    _isVibrating = false;
    notifyListeners();
  }

  Future<void> stop() async {
    _liveTimer?.cancel();
    _liveTimer = null;
    _queue.clear();
    try {
      await Vibration.cancel();
    } catch (_) {}
    _isVibrating = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    _queue.clear();
    super.dispose();
  }
}
