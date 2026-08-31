import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/device_model.dart';

class DeviceService extends ChangeNotifier {
  String _myDeviceId = '';
  String _myDeviceName = 'Mening Telefonim';
  List<DeviceModel> _pairedDevices = [];
  DeviceModel? _activeDevice;

  String get myDeviceId => _myDeviceId;
  String get myDeviceName => _myDeviceName;
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
      final shortUuid = const Uuid().v4().replaceAll('-', '').substring(0, 8).toUpperCase();
      _myDeviceId = 'VL-$shortUuid';
      await prefs.setString('my_device_id', _myDeviceId);
    }
    _myDeviceName = prefs.getString('my_device_name') ?? 'Telefon ${Random().nextInt(900) + 100}';

    final devicesJson = prefs.getString('paired_devices') ?? '[]';
    final List decoded = jsonDecode(devicesJson);
    _pairedDevices = decoded.map((d) => DeviceModel.fromJson(d)).toList();

    // Auto-sanitize: Remove any temporary 6-digit PIN entries or self entries
    _pairedDevices.removeWhere((d) =>
      (d.id.length == 6 && int.tryParse(d.id) != null) || d.id == _myDeviceId
    );

    final activeId = prefs.getString('active_device_id');
    if (activeId != null) {
      final found = _pairedDevices.where((d) => d.id == activeId);
      if (found.isNotEmpty) {
        _activeDevice = found.first;
      } else if (_pairedDevices.isNotEmpty) {
        _activeDevice = _pairedDevices.first;
      }
    } else if (_pairedDevices.isNotEmpty) {
      _activeDevice = _pairedDevices.first;
    }
    notifyListeners();
  }

  Future<void> setMyDeviceName(String name) async {
    _myDeviceName = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('my_device_name', name);
    notifyListeners();
  }

  String generatePairingCode() {
    // Generate simple 6-digit PIN (e.g. 583291)
    final rand = Random.secure();
    _currentCode = (rand.nextInt(900000) + 100000).toString();
    _codeExpiry = DateTime.now().add(const Duration(minutes: 15));
    _codeUsed = false;
    notifyListeners();
    return _currentCode;
  }

  bool validateCode(String code) {
    if (!codeIsValid) return false;
    return code.replaceAll(' ', '').toUpperCase() == _currentCode;
  }

  void markCodeUsed() {
    _codeUsed = true;
    notifyListeners();
  }

  Future<DeviceModel> addDevice({required String peerId, String name = ''}) async {
    final cleanId = peerId.trim().replaceAll(' ', '').toUpperCase();
    final existingIndex = _pairedDevices.indexWhere((d) => d.id == cleanId);
    if (existingIndex >= 0) {
      if (name.trim().isNotEmpty) {
        _pairedDevices[existingIndex].name = name.trim();
      }
      _pairedDevices[existingIndex].status = 'online';
      _activeDevice = _pairedDevices[existingIndex];
      await _save();
      notifyListeners();
      return _pairedDevices[existingIndex];
    }

    final deviceName = name.trim().isEmpty ? 'Phone ${_pairedDevices.length + 1}' : name.trim();
    final device = DeviceModel(
      id: cleanId,
      name: deviceName,
      status: 'online',
      lastSeen: DateTime.now(),
      isActive: true,
    );
    _pairedDevices.add(device);
    _activeDevice = device;
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
    _save();
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
