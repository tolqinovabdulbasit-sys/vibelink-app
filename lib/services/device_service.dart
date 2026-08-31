import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/device_model.dart';

class DeviceService extends ChangeNotifier {
  String _myDeviceId = '';
  List<DeviceModel> _pairedDevices = [];
  DeviceModel? _activeDevice;

  String get myDeviceId => _myDeviceId;
  List<DeviceModel> get pairedDevices => List.unmodifiable(_pairedDevices);
  DeviceModel? get activeDevice => _activeDevice;

  // Pairing code state
  String _currentCode = '';
  DateTime? _codeExpiry;
  bool _codeUsed = false;

  String get currentCode => _currentCode;
  DateTime? get codeExpiry => _codeExpiry;
  bool get codeIsValid =>
      _currentCode.isNotEmpty &&
      _codeExpiry != null &&
      DateTime.now().isBefore(_codeExpiry!) &&
      !_codeUsed;

  DeviceService() {
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _myDeviceId = prefs.getString('my_device_id') ?? '';
    if (_myDeviceId.isEmpty) {
      _myDeviceId = const Uuid().v4().replaceAll('-', '').substring(0, 16).toUpperCase();
      await prefs.setString('my_device_id', _myDeviceId);
    }

    final devicesJson = prefs.getString('paired_devices') ?? '[]';
    final List decoded = jsonDecode(devicesJson);
    _pairedDevices = decoded.map((d) => DeviceModel.fromJson(d)).toList();

    final activeId = prefs.getString('active_device_id');
    if (activeId != null) {
      _activeDevice = _pairedDevices.firstWhere(
        (d) => d.id == activeId,
        orElse: () => _pairedDevices.isNotEmpty ? _pairedDevices.first : DeviceModel(id: '', name: ''),
      );
      if (_activeDevice!.id.isEmpty) _activeDevice = null;
    } else if (_pairedDevices.isNotEmpty) {
      _activeDevice = _pairedDevices.first;
    }
    notifyListeners();
  }

  String generatePairingCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random.secure();
    _currentCode = List.generate(8, (_) => chars[rand.nextInt(chars.length)]).join();
    _codeExpiry = DateTime.now().add(const Duration(minutes: 15));
    _codeUsed = false;
    notifyListeners();
    return _currentCode;
  }

  bool validateCode(String code) {
    if (!codeIsValid) return false;
    return code.toUpperCase() == _currentCode.toUpperCase();
  }

  void markCodeUsed() {
    _codeUsed = true;
    notifyListeners();
  }

  Future<DeviceModel> addDevice({required String peerId, String name = ''}) async {
    final deviceName = name.trim().isEmpty ? 'Qurilma ${_pairedDevices.length + 1}' : name.trim();
    final device = DeviceModel(
      id: peerId,
      name: deviceName,
      status: 'online',
      lastSeen: DateTime.now(),
      isActive: _pairedDevices.isEmpty,
    );
    _pairedDevices.add(device);
    if (_pairedDevices.length == 1) _activeDevice = device;
    await _save();
    notifyListeners();
    return device;
  }

  Future<void> renameDevice(String id, String newName) async {
    final idx = _pairedDevices.indexWhere((d) => d.id == id);
    if (idx >= 0) {
      _pairedDevices[idx].name = newName;
      if (_activeDevice?.id == id) _activeDevice!.name = newName;
      await _save();
      notifyListeners();
    }
  }

  Future<void> removeDevice(String id) async {
    _pairedDevices.removeWhere((d) => d.id == id);
    if (_activeDevice?.id == id) {
      _activeDevice = _pairedDevices.isNotEmpty ? _pairedDevices.first : null;
    }
    await _save();
    notifyListeners();
  }

  void setActiveDevice(DeviceModel device) {
    _activeDevice = device;
    notifyListeners();
  }

  void updateDeviceStatus(String id, String status) {
    final idx = _pairedDevices.indexWhere((d) => d.id == id);
    if (idx >= 0) {
      _pairedDevices[idx].status = status;
      if (status == 'online') _pairedDevices[idx].lastSeen = DateTime.now();
      if (_activeDevice?.id == id) _activeDevice!.status = status;
      notifyListeners();
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('paired_devices',
      jsonEncode(_pairedDevices.map((d) => d.toJson()).toList()));
    if (_activeDevice != null) {
      await prefs.setString('active_device_id', _activeDevice!.id);
    }
  }
}
