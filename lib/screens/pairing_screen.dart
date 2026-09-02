import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/device_service.dart';
import '../services/peer_service.dart';

class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key});
  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final _peerIdController = TextEditingController();
  final _myIdController = TextEditingController();
  bool _connecting = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    final ds = context.read<DeviceService>();
    _myIdController.text = ds.myDeviceId;
  }

  @override
  void dispose() {
    _peerIdController.dispose();
    _myIdController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final rawPeer = _peerIdController.text.trim();
    if (rawPeer.isEmpty) {
      setState(() => _errorMsg = "Sherik ID raqamini kiriting (masalan: 02)");
      return;
    }

    final cleanPeer = rawPeer.padLeft(2, '0');
    final ds = context.read<DeviceService>();
    final ps = context.read<PeerService>();

    if (cleanPeer == ds.myDeviceId) {
      setState(() => _errorMsg = "O'z ID raqamingizni kirita olmaysiz!");
      return;
    }

    setState(() {
      _connecting = true;
      _errorMsg = null;
    });

    final device = await ds.addDevice(
      peerId: cleanPeer,
      name: 'Sherik $cleanPeer',
    );

    final sharedChannel = PeerService.getPairChannel(ds.myDeviceId, cleanPeer);
    await ps.joinChannel(sharedChannel);
    ps.setTarget(cleanPeer);
    ps.sendHello(ds.myDeviceName);

    if (mounted) {
      setState(() => _connecting = false);
      _showSuccessDialog("ID: $cleanPeer bilan ulanish o'rnatildi! 🟢");
    }
  }

  Future<void> _updateMyId() async {
    final newId = _myIdController.text.trim();
    if (newId.isEmpty) return;
    final ds = context.read<DeviceService>();
    final ps = context.read<PeerService>();

    await ds.setMyDeviceId(newId);
    ps.init(ds.myDeviceId);

    if (ds.activeDevice != null) {
      final sharedChannel = PeerService.getPairChannel(ds.myDeviceId, ds.activeDevice!.id);
      await ps.joinChannel(sharedChannel);
    }
    _showToast("Mening ID yangilandi: ${ds.myDeviceId}");
  }

  void _showToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFF6C63FF),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showSuccessDialog(String msg) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF12122A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Color(0xFF22C55E), size: 28),
            SizedBox(width: 10),
            Text('Ulandi!', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(msg, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: Color(0xFF6C63FF), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ds = context.watch<DeviceService>();

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Qurilmalar va Ulanish', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. My Permanent Device ID Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1E1B4B), Color(0xFF171738)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.4)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Mening Doimiy ID Raqamim',
                          style: TextStyle(fontSize: 13, color: Colors.white70, fontWeight: FontWeight.w600),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_rounded, color: Color(0xFF00D4FF), size: 18),
                          onPressed: () => _showEditIdDialog(ds),
                          tooltip: "ID ni o'zgartirish",
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF00D4FF).withOpacity(0.5)),
                      ),
                      child: Text(
                        ds.myDeviceId,
                        style: const TextStyle(
                          fontSize: 42,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF00D4FF),
                          letterSpacing: 4,
                          fontFamily: 'JetBrains Mono',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "Ushbu raqamni sherigingiz o'z telefoniga kiritishi kerak",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.5)),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // 2. Connect to Partner Phone
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF12122A),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.06)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Sherik Telefon ID Raqami',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Ikkinchi telefondagi 2 xonali ID raqamni kiriting (masalan: 02)',
                      style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.5)),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _peerIdController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF22C55E),
                        letterSpacing: 3,
                      ),
                      decoration: InputDecoration(
                        hintText: '02',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 24),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.05),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: Color(0xFF22C55E), width: 2),
                        ),
                      ),
                    ),

                    if (_errorMsg != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(_errorMsg!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12)),
                      ),
                    ],

                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _connecting ? null : _connect,
                        icon: _connecting
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.link_rounded, size: 20),
                        label: Text(_connecting ? 'Ulanmoqda...' : 'Ulanish', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF22C55E),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // 3. Paired Devices List
              if (ds.pairedDevices.isNotEmpty) ...[
                const Text(
                  'Saqlangan Sheriklar',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
                ),
                const SizedBox(height: 10),
                ...ds.pairedDevices.map((d) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF12122A),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: ds.activeDevice?.id == d.id ? const Color(0xFF22C55E).withOpacity(0.5) : Colors.white.withOpacity(0.04),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: d.status == 'online' ? const Color(0xFF22C55E) : Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(d.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
                            Text("ID: ${d.id}", style: const TextStyle(fontSize: 11, color: Color(0xFF00D4FF), fontFamily: 'JetBrains Mono')),
                          ],
                        ),
                      ),
                      if (ds.activeDevice?.id == d.id)
                        const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: Icon(Icons.check_circle_rounded, color: Color(0xFF22C55E), size: 20),
                        )
                      else
                        TextButton(
                          onPressed: () {
                            ds.setActiveDevice(d);
                            context.read<PeerService>().connectWithPeer(d.id);
                          },
                          child: const Text('Tanlash', style: TextStyle(color: Color(0xFF6C63FF), fontSize: 12)),
                        ),
                      IconButton(
                        icon: Icon(Icons.delete_outline_rounded, color: Colors.red.withOpacity(0.6), size: 20),
                        onPressed: () => ds.removeDevice(d.id),
                      ),
                    ],
                  ),
                )),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showEditIdDialog(DeviceService ds) {
    _myIdController.text = ds.myDeviceId;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF12122A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("O'z ID raqamingizni sozlash", style: TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: _myIdController,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: const TextStyle(fontFamily: 'JetBrains Mono', fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF00D4FF)),
          decoration: const InputDecoration(
            hintText: '01',
            hintStyle: TextStyle(color: Colors.white24),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Bekor qilish', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            onPressed: () {
              _updateMyId();
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6C63FF)),
            child: const Text('Saqlash'),
          ),
        ],
      ),
    );
  }
}
