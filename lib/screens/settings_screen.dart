import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/device_service.dart';
import '../models/vibration_pattern.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notifications = true;
  bool _bgMode = true;

  void _copyId(String id) {
    Clipboard.setData(ClipboardData(text: id));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: const Text('ID nusxalandi'), backgroundColor: const Color(0xFF6C63FF),
        behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
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
              if (ctrl.text.trim().isNotEmpty) context.read<DeviceService>().renameDevice(id, ctrl.text.trim());
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
            const SizedBox(height: 20),

            // My device card
            Consumer<DeviceService>(
              builder: (_, ds, __) => _buildMyDeviceCard(ds),
            ),
            const SizedBox(height: 20),

            // Paired devices
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Juftlangan Qurilmalar',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
              ],
            ),
            const SizedBox(height: 12),
            Consumer<DeviceService>(
              builder: (_, ds, __) {
                if (ds.pairedDevices.isEmpty) return _buildEmptyDevices();
                return Column(
                  children: ds.pairedDevices.map((d) => _DeviceTile(
                    device: d,
                    isActive: ds.activeDevice?.id == d.id,
                    onTap: () => ds.setActiveDevice(d),
                    onRename: () => _showRenameDialog(context, d.id, d.name),
                    onDelete: () => _showDeleteDialog(context, d.id, d.name),
                  )).toList(),
                );
              },
            ),
            const SizedBox(height: 24),

            // Vibration types
            const Text('Vibratsiya Tiplari (10 ta)',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
            const SizedBox(height: 12),
            ...kBuiltinPresets.asMap().entries.map((e) => _VibTypeTile(
              num: e.key + 1,
              pattern: e.value,
            )),

            const SizedBox(height: 24),

            // App settings
            const Text('Ilova Sozlamalari',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
            const SizedBox(height: 12),
            _SettingsTile(
              icon: '🌐',
              title: 'Til',
              subtitle: 'Русский',
              trailing: Icon(Icons.chevron_right_rounded, color: Colors.white.withOpacity(0.3)),
            ),
            _SettingsTile(
              icon: '🔔',
              title: 'Bildirishnomalar',
              subtitle: _notifications ? 'Yoqilgan' : "O'chirilgan",
              trailing: Switch(
                value: _notifications,
                onChanged: (v) => setState(() => _notifications = v),
                activeColor: const Color(0xFF6C63FF),
              ),
            ),
            _SettingsTile(
              icon: '📳',
              title: 'Fon rejimi',
              subtitle: "Fonda ishlash",
              trailing: Switch(
                value: _bgMode,
                onChanged: (v) => setState(() => _bgMode = v),
                activeColor: const Color(0xFF6C63FF),
              ),
            ),
            _SettingsTile(
              icon: 'ℹ️',
              title: 'Versiya',
              subtitle: 'VibeLink v1.0.0',
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildMyDeviceCard(DeviceService ds) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: [const Color(0xFF6C63FF).withOpacity(0.2), const Color(0xFF00D4FF).withOpacity(0.1)]),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.2)),
    ),
    child: Row(
      children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF6C63FF).withOpacity(0.2),
          ),
          child: const Icon(Icons.phone_android_rounded, color: Color(0xFF6C63FF), size: 24),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Bu qurilma', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
              Text('ID: ${ds.myDeviceId.substring(0, 8)}...', style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.5), fontFamily: 'JetBrains Mono')),
            ],
          ),
        ),
        IconButton(
          onPressed: () => _copyId(ds.myDeviceId),
          icon: Icon(Icons.copy_rounded, color: Colors.white.withOpacity(0.5), size: 18),
        ),
      ],
    ),
  );

  Widget _buildEmptyDevices() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(32),
    decoration: BoxDecoration(color: const Color(0xFF12122A), borderRadius: BorderRadius.circular(16)),
    child: Column(
      children: [
        Icon(Icons.phone_android_rounded, size: 48, color: Colors.white.withOpacity(0.2)),
        const SizedBox(height: 12),
        Text("Qurilmalar yo'q", style: TextStyle(color: Colors.white.withOpacity(0.3))),
        const SizedBox(height: 4),
        Text("Qurilma qo'shish uchun \"Устройства\" bo'limiga o'ting",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.2))),
      ],
    ),
  );
}

class _DeviceTile extends StatelessWidget {
  final dynamic device;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  const _DeviceTile({required this.device, required this.isActive, required this.onTap, required this.onRename, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final status = device.status as String;
    final statusColor = status == 'online' ? const Color(0xFF22C55E)
        : status == 'connecting' ? const Color(0xFFF59E0B)
        : Colors.white.withOpacity(0.3);
    final statusLabel = status == 'online' ? 'Onlayn' : status == 'connecting' ? 'Ulanmoqda' : 'Oflayn';

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF12122A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isActive ? const Color(0xFF6C63FF).withOpacity(0.4) : Colors.white.withOpacity(0.06), width: isActive ? 1.5 : 1),
        ),
        child: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: statusColor.withOpacity(0.15),
              ),
              child: Icon(Icons.phone_android_rounded, color: statusColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(device.name as String, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
                  Text(statusLabel, style: TextStyle(fontSize: 12, color: statusColor)),
                ],
              ),
            ),
            if (isActive)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF6C63FF).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('Aktiv', style: TextStyle(fontSize: 10, color: Color(0xFF6C63FF), fontWeight: FontWeight.w600)),
              ),
            IconButton(onPressed: onRename, icon: Icon(Icons.edit_rounded, color: Colors.white.withOpacity(0.4), size: 18)),
            IconButton(onPressed: onDelete, icon: Icon(Icons.delete_outline_rounded, color: const Color(0xFFEF4444).withOpacity(0.6), size: 18)),
          ],
        ),
      ),
    );
  }
}

class _VibTypeTile extends StatelessWidget {
  final int num;
  final VibrationPattern pattern;
  const _VibTypeTile({required this.num, required this.pattern});

  @override
  Widget build(BuildContext context) {
    final color = Color(int.parse(pattern.colorHex.replaceFirst('#', '0xFF')));
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF12122A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color.withOpacity(0.15)),
            alignment: Alignment.center,
            child: Text('$num', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
          ),
          const SizedBox(width: 12),
          // Pattern dots visual
          Row(
            children: pattern.steps.take(4).map((s) => Container(
              width: s.type == 'vibrate' ? (s.durationMs > 300 ? 24.0 : 10.0) : 6.0,
              height: s.type == 'vibrate' ? 8.0 : 4.0,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: s.type == 'vibrate' ? color : Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
            )).toList(),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(pattern.name, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13))),
          Icon(Icons.chevron_right_rounded, color: Colors.white.withOpacity(0.2), size: 18),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final String icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  const _SettingsTile({required this.icon, required this.title, required this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(color: const Color(0xFF12122A), borderRadius: BorderRadius.circular(12)),
    child: Row(
      children: [
        Text(icon, style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 14),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.white)),
            Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.4))),
          ],
        )),
        if (trailing != null) trailing!,
      ],
    ),
  );
}
