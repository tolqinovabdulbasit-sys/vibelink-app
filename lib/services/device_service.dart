import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  DeviceService() {
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _myDeviceId = prefs.getString('my_device_id_v2') ?? '';

    if (_myDeviceId.isEmpty) {
      // Allocate persistent short numeric ID ("01", "02", ...)
      // If previous user had old ID or new install, start counter or generate simple 2-digit ID
      final savedNum = prefs.getInt('device_numeric_id');
      if (savedNum != null && savedNum > 0) {
        _myDeviceId = savedNum.toString().padLeft(2, '0');
      } else {
        // New install: assign a unique random 2-digit ID (10–99) to avoid collisions
        final rnd = Random().nextInt(90) + 10; // always 2-digit: 10 to 99
        _myDeviceId = rnd.toString();
        await prefs.setInt('device_numeric_id', rnd);
      }
      await prefs.setString('my_device_id_v2', _myDeviceId);
    }

    _myDeviceName = prefs.getString('my_device_name') ?? 'Telefon $_myDeviceId';

    final devicesJson = prefs.getString('paired_devices') ?? '[]';
    try {
      final List decoded = jsonDecode(devicesJson);
      _pairedDevices = decoded.map((d) => DeviceModel.fromJson(d)).toList();
    } catch (_) {
      _pairedDevices = [];
    }

    // Auto-sanitize: remove any self entries
    _pairedDevices.removeWhere((d) => d.id == _myDeviceId);

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

  Future<void> setMyDeviceId(String newId) async {
    final cleanId = newId.trim().padLeft(2, '0');
    if (cleanId.isEmpty) return;
    _myDeviceId = cleanId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('my_device_id_v2', _myDeviceId);
    _pairedDevices.removeWhere((d) => d.id == _myDeviceId);
    notifyListeners();
  }

  Future<void> setMyDeviceName(String name) async {
    _myDeviceName = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('my_device_name', name);
    notifyListeners();
  }

  Future<DeviceModel> addDevice({required String peerId, String name = ''}) async {
    final cleanId = peerId.trim().padLeft(2, '0');
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

    final deviceName = name.trim().isEmpty ? 'Sherik $cleanId' : name.trim();
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
