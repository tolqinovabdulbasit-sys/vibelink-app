import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../services/device_service.dart';
import '../services/vibration_service.dart';
import '../services/peer_service.dart';
import '../services/relay_backend.dart';
import '../models/vibration_pattern.dart';
import '../models/device_model.dart';

class SettingsScreen extends StatefulWidget {
  final Function(int)? onNavigateTab;
  const SettingsScreen({super.key, this.onNavigateTab});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notifications = true;
  bool _bgMode = true;
  String _selectedLang = 'Русский';
  Map<RelayType, bool?> _testResults = {};
  RelayType? _testingType;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _notifications = prefs.getBool('notifications_enabled') ?? true;
      _bgMode = prefs.getBool('bg_mode_enabled') ?? true;
      _selectedLang = prefs.getString('app_language') ?? 'Русский';
    });
    if (_bgMode) {
      WakelockPlus.enable();
    }
  }

  Future<void> _toggleNotifications(bool val) async {
    setState(() => _notifications = val);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifications_enabled', val);
    _showSnack(_notifications ? "Bildirishnomalar yoqildi" : "Bildirishnomalar o'chirildi");
  }

  Future<void> _toggleBgMode(bool val) async {
    setState(() => _bgMode = val);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('bg_mode_enabled', val);
    if (val) {
      WakelockPlus.enable();
      _showSnack("Doimiy fon rejimi faollashtirildi");
    } else {
      WakelockPlus.disable();
      _showSnack("Fon rejimi o'chirildi");
    }
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

  void _copyId(String id) {
    Clipboard.setData(ClipboardData(text: id));
    _showSnack('ID nusxalandi: $id');
  }

  void _showLanguageDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF12122A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Tilni tanlang', style: TextStyle(color: Colors.white, fontSize: 18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _langOption('Русский'),
            _langOption("O'zbekcha"),
            _langOption('English'),
          ],
        ),
      ),
    );
  }

  Widget _langOption(String lang) {
    final isSel = _selectedLang == lang;
    return InkWell(
      onTap: () async {
        setState(() => _selectedLang = lang);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('app_language', lang);
        Navigator.pop(context);
        _showSnack("Til tanlandi: $lang");
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(lang, style: TextStyle(color: isSel ? const Color(0xFF00D4FF) : Colors.white, fontSize: 15, fontWeight: isSel ? FontWeight.w700 : FontWeight.w400)),
            if (isSel) const Icon(Icons.check_circle_rounded, color: Color(0xFF00D4FF), size: 20),
          ],
        ),
      ),
    );
  }

  void _showVersionDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF12122A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.vibration_rounded, color: Color(0xFF6C63FF)),
            SizedBox(width: 8),
            Text('VibeLink v1.1.0', style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Real-Vaqtli Masofaviy Vibratsiya Boshqaruv Tizimi', style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 12),
            Text('• 3 xil transport backend (WSS / Stream / Poll)', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12)),
            Text('• Port 443 (HTTPS) — hech qachon bloklanmaydi', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12)),
            Text('• 10 ta o\'rnatilgan vibro-signal', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12)),
            Text('• Shaxsiy Pattern Studio', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12)),
            Text('• 0ms javob beruvchi Live Touch', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: Color(0xFF6C63FF))),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(BuildContext context, String id, String currentName) {
    final ctrl = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF12122A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Qurilma nomini tahrirlash', style: TextStyle(color: Colors.white, fontSize: 17)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 20,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            filled: true, fillColor: Colors.white.withOpacity(0.06),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            counterText: '',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Bekor', style: TextStyle(color: Colors.white.withOpacity(0.5)))),
          TextButton(
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) {
                context.read<DeviceService>().renameDevice(id, ctrl.text.trim());
              }
              Navigator.pop(context);
            },
            child: const Text('Saqlash', style: TextStyle(color: Color(0xFF6C63FF))),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, String id, String name) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF12122A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Qurilmani o'chirish", style: TextStyle(color: Colors.white, fontSize: 17)),
        content: Text('$name ni juftlangan ro\'yxatdan o\'chirmoqchimisiz?',
          style: TextStyle(color: Colors.white.withOpacity(0.7))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Bekor', style: TextStyle(color: Colors.white.withOpacity(0.5)))),
          TextButton(
            onPressed: () {
              context.read<DeviceService>().removeDevice(id);
              Navigator.pop(context);
            },
            child: const Text("O'chirish", style: TextStyle(color: Color(0xFFEF4444))),
          ),
        ],
      ),
    );
  }

  void _testOrSendPreset(VibrationPattern pattern) {
    final vibeService = context.read<VibrationService>();
    final peerService = context.read<PeerService>();
    final devService = context.read<DeviceService>();

    // Test on this phone immediately
    vibeService.playPattern(pattern);
    HapticFeedback.mediumImpact();

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF12122A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(pattern.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
            const SizedBox(height: 8),
            Text('Telefoningizda sinovdan o\'tkazildi! Sherik qurilmaga yuborilsinmi?',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13)),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => vibeService.playPattern(pattern),
                    icon: const Icon(Icons.replay_rounded, size: 16),
                    label: const Text('Qayta sinash'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: Colors.white.withOpacity(0.2)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      final active = devService.activeDevice;
                      if (active != null) {
                        peerService.sendPattern(pattern, active.id);
                        Navigator.pop(context);
                        _showSnack('${active.name}ga yuborildi!');
                      } else {
                        _showSnack('Qurilma ulanmagan!');
                      }
                    },
                    icon: const Icon(Icons.send_rounded, size: 16),
                    label: const Text('Sherikka yubor'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C63FF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Switch transport backend
  // ──────────────────────────────────────────────

  Future<void> _switchTransport(RelayType type) async {
    final ps = context.read<PeerService>();
    setState(() => _testingType = type);
    
    await ps.switchBackend(type);
    
    setState(() => _testingType = null);
    _showSnack('${type.label} ga almashtirildi!');
  }

  Future<void> _testTransport(RelayType type) async {
    setState(() {
      _testingType = type;
      _testResults[type] = null; // null = testing
    });

    final ps = context.read<PeerService>();
    final result = await ps.testBackend(type);

    setState(() {
      _testResults[type] = result;
      _testingType = null;
    });

    _showSnack(result
        ? '✅ ${type.shortLabel} ishlaydi!'
        : '❌ ${type.shortLabel} ishlamadi');
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(child: Text('Sozlamalar',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white))),
            const SizedBox(height: 18),

            // My device card
            Consumer<DeviceService>(
              builder: (_, ds, __) => _buildMyDeviceCard(ds),
            ),
            const SizedBox(height: 18),

            // ═══════════════════════════════════════
            // 🔥 TRANSPORT BACKEND SWITCHER
            // ═══════════════════════════════════════
            const Text('🚀 Transport (Ulanish turi)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
            const SizedBox(height: 4),
            Text('Biri ishlamasa, boshqasini tanlang — qayta o\'rnatish shart emas!',
              style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.5))),
            const SizedBox(height: 10),
            Consumer<PeerService>(
              builder: (_, ps, __) => Column(
                children: RelayType.values.map((type) => 
                  _buildTransportTile(type, ps.relayType == type),
                ).toList(),
              ),
            ),
            const SizedBox(height: 18),

            // Paired devices header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Juftlangan Qurilmalar',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                TextButton.icon(
                  onPressed: () {
                    widget.onNavigateTab?.call(1); // Switch to Pairing Tab
                  },
                  icon: const Icon(Icons.add_rounded, size: 18, color: Color(0xFF6C63FF)),
                  label: const Text('Qo\'shish', style: TextStyle(color: Color(0xFF6C63FF), fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Consumer<DeviceService>(
              builder: (ctx, ds, __) {
                if (ds.pairedDevices.isEmpty) return _buildEmptyDevices();
                return Column(
                  children: ds.pairedDevices.map((d) => _DeviceTile(
                    device: d,
                    isActive: ds.activeDevice?.id == d.id,
                    onTap: () {
                      ds.setActiveDevice(d);
                      ctx.read<PeerService>().setTarget(d.id);
                      _showSnack("${d.name} asosiy qurilma sifatida tanlandi");
                    },
                    onRename: () => _showRenameDialog(context, d.id, d.name),
                    onDelete: () => _showDeleteDialog(context, d.id, d.name),
                  )).toList(),
                );
              },
            ),
            const SizedBox(height: 20),

            // 10 Vibration types
            const Text('Vibratsiya Tiplari (10 ta)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
            const SizedBox(height: 10),
            ...kBuiltinPresets.asMap().entries.map((e) => _VibTypeTile(
              num: e.key + 1,
              pattern: e.value,
              onTap: () => _testOrSendPreset(e.value),
            )),

            const SizedBox(height: 20),

            // App settings
            const Text('Ilova Sozlamalari',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
            const SizedBox(height: 10),
            _SettingsTile(
              icon: '🌐',
              title: 'Til',
              subtitle: _selectedLang,
              onTap: _showLanguageDialog,
              trailing: Icon(Icons.chevron_right_rounded, color: Colors.white.withOpacity(0.3)),
            ),
            _SettingsTile(
              icon: '🔔',
              title: 'Bildirishnomalar',
              subtitle: _notifications ? 'Yoqilgan' : "O'chirilgan",
              trailing: Switch(
                value: _notifications,
                onChanged: _toggleNotifications,
                activeColor: const Color(0xFF6C63FF),
              ),
            ),
            _SettingsTile(
              icon: '📳',
              title: 'Fon rejimi (Wakelock)',
              subtitle: _bgMode ? "Ekran o'chganda ham tayyor" : "O'chirilgan",
              trailing: Switch(
                value: _bgMode,
                onChanged: _toggleBgMode,
                activeColor: const Color(0xFF6C63FF),
              ),
            ),
            _SettingsTile(
              icon: 'ℹ️',
              title: 'Versiya',
              subtitle: 'VibeLink v1.1.0',
              onTap: _showVersionDialog,
              trailing: Icon(Icons.chevron_right_rounded, color: Colors.white.withOpacity(0.3)),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Transport tile with test button
  // ──────────────────────────────────────────────

  Widget _buildTransportTile(RelayType type, bool isActive) {
    final testResult = _testResults[type];
    final isTesting = _testingType == type;

    // Icon
    IconData iconData;
    switch (type) {
      case RelayType.websocket:  iconData = Icons.bolt_rounded; break;
      case RelayType.httpStream: iconData = Icons.stream_rounded; break;
      case RelayType.httpPoll:   iconData = Icons.sync_rounded; break;
    }

    // Border/accent color
    Color accentColor;
    if (isActive) {
      accentColor = const Color(0xFF6C63FF);
    } else if (testResult == true) {
      accentColor = const Color(0xFF22C55E);
    } else if (testResult == false) {
      accentColor = const Color(0xFFEF4444);
    } else {
      accentColor = Colors.white.withOpacity(0.08);
    }

    return GestureDetector(
      onTap: () => _switchTransport(type),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF6C63FF).withOpacity(0.12) : const Color(0xFF12122A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accentColor, width: isActive ? 1.8 : 1),
        ),
        child: Row(
          children: [
            // Icon
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (isActive ? const Color(0xFF6C63FF) : Colors.white).withOpacity(0.1),
              ),
              child: Icon(iconData, color: isActive ? const Color(0xFF6C63FF) : Colors.white54, size: 18),
            ),
            const SizedBox(width: 12),
            // Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    type.shortLabel,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: isActive ? Colors.white : Colors.white.withOpacity(0.85),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    type.description,
                    style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.5)),
                  ),
                ],
              ),
            ),
            // Test button
            GestureDetector(
              onTap: () => _testTransport(type),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: isTesting
                    ? const SizedBox(
                        width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6C63FF)),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (testResult == true)
                            const Icon(Icons.check_circle, color: Color(0xFF22C55E), size: 14)
                          else if (testResult == false)
                            const Icon(Icons.cancel, color: Color(0xFFEF4444), size: 14)
                          else
                            const Icon(Icons.speed_rounded, color: Colors.white54, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            testResult == true ? 'OK' : testResult == false ? 'Xato' : 'Test',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: testResult == true
                                  ? const Color(0xFF22C55E)
                                  : testResult == false
                                      ? const Color(0xFFEF4444)
                                      : Colors.white54,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(width: 6),
            // Active checkmark
            if (isActive)
              const Icon(Icons.check_circle_rounded, color: Color(0xFF6C63FF), size: 20)
            else
              Icon(Icons.radio_button_off_rounded, color: Colors.white.withOpacity(0.2), size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildMyDeviceCard(DeviceService ds) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [const Color(0xFF6C63FF).withOpacity(0.2), const Color(0xFF00D4FF).withOpacity(0.1)],
      ),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.3)),
    ),
    child: Row(
      children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF6C63FF).withOpacity(0.2),
          ),
          child: const Icon(Icons.phone_android_rounded, color: Color(0xFF6C63FF), size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(ds.myDeviceName, style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white, fontSize: 14)),
              const SizedBox(height: 2),
              Text('ID: ${ds.myDeviceId}', style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.6), fontFamily: 'JetBrains Mono')),
            ],
          ),
        ),
        IconButton(
          onPressed: () => _copyId(ds.myDeviceId),
          icon: Icon(Icons.copy_rounded, color: Colors.white.withOpacity(0.7), size: 18),
        ),
      ],
    ),
  );

  Widget _buildEmptyDevices() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(color: const Color(0xFF12122A), borderRadius: BorderRadius.circular(16)),
    child: Column(
      children: [
        Icon(Icons.devices_rounded, size: 36, color: Colors.white.withOpacity(0.25)),
        const SizedBox(height: 8),
        Text("Juftlangan qurilmalar yo'q", style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13)),
        const SizedBox(height: 4),
        Text("Qurilma qo'shish uchun yuqoridagi '+ Qo'shish' tugmasini bosing",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.3))),
      ],
    ),
  );
}

class _DeviceTile extends StatelessWidget {
  final DeviceModel device;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  const _DeviceTile({required this.device, required this.isActive, required this.onTap, required this.onRename, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final ps = context.watch<PeerService>();
    final isOnline = isActive && ps.isPeerOnline;
    final statusColor = isOnline ? const Color(0xFF22C55E) : Colors.white24;
    final statusLabel = isOnline ? 'Onlayn' : 'Oflayn';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF12122A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive ? const Color(0xFF6C63FF).withOpacity(0.6) : Colors.white.withOpacity(0.06),
            width: isActive ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: statusColor.withOpacity(0.15),
              ),
              child: Icon(Icons.phone_android_rounded, color: isOnline ? statusColor : Colors.white54, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(device.name, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white, fontSize: 13)),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: statusColor)),
                      const SizedBox(width: 6),
                      Text(statusLabel, style: TextStyle(fontSize: 11, color: isOnline ? statusColor : Colors.white38)),
                    ],
                  ),
                ],
              ),
            ),
            if (isActive)
              Container(
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF6C63FF).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('Aktiv', style: TextStyle(fontSize: 10, color: Color(0xFF6C63FF), fontWeight: FontWeight.w700)),
              ),
            IconButton(onPressed: onRename, icon: Icon(Icons.edit_rounded, color: Colors.white.withOpacity(0.4), size: 17)),
            IconButton(onPressed: onDelete, icon: Icon(Icons.delete_outline_rounded, color: const Color(0xFFEF4444).withOpacity(0.6), size: 17)),
          ],
        ),
      ),
    );
  }
}

class _VibTypeTile extends StatelessWidget {
  final int num;
  final VibrationPattern pattern;
  final VoidCallback onTap;
  const _VibTypeTile({required this.num, required this.pattern, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = Color(int.parse(pattern.colorHex.replaceFirst('#', '0xFF')));
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF12122A),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 26, height: 26,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color.withOpacity(0.15)),
              alignment: Alignment.center,
              child: Text('$num', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
            ),
            const SizedBox(width: 12),
            Text(pattern.icon, style: TextStyle(color: color, fontSize: 13, fontFamily: 'JetBrains Mono', fontWeight: FontWeight.w700)),
            const SizedBox(width: 12),
            Expanded(child: Text(pattern.name, style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 13))),
            Icon(Icons.play_circle_fill_rounded, color: color.withOpacity(0.7), size: 20),
          ],
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final String icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  const _SettingsTile({required this.icon, required this.title, required this.subtitle, this.trailing, this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: const Color(0xFF12122A), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.white, fontSize: 13)),
              Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.4))),
            ],
          )),
          if (trailing != null) trailing!,
        ],
      ),
    ),
  );
}
