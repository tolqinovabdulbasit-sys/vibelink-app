import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/device_service.dart';
import '../services/peer_service.dart';

class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key});
  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  bool _showCode = true;
  Timer? _timer;
  Duration _remaining = Duration.zero;
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  bool _connecting = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initPairing();
    });
  }

  void _initPairing() {
    final ds = context.read<DeviceService>();
    final ps = context.read<PeerService>();

    // Generate 6-digit simple PIN
    ds.generatePairingCode();
    ps.joinChannel(ds.currentCode);
    _startTimer(ds);

    // When partner phone joins
    ps.onPeerJoined = (peerId, name) async {
      final device = await ds.addDevice(
        peerId: peerId.isNotEmpty ? peerId : ds.currentCode,
        name: name.isNotEmpty ? name : 'Sherik Telefon',
      );
      ps.setTarget(device.id);
      if (mounted) {
        setState(() => _connecting = false);
        _showSuccessDialog("${device.name} bilan ulanish o'rnatildi!");
      }
    };
  }

  void _generateNewCode() {
    final ds = context.read<DeviceService>();
    final ps = context.read<PeerService>();
    ds.generatePairingCode();
    ps.joinChannel(ds.currentCode);
    _startTimer(ds);
    _showToast('Yangi PIN kod: ${ds.currentCode}');
  }

  void _startTimer(DeviceService ds) {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final expiry = ds.codeExpiry;
      if (expiry == null) return;
      final rem = expiry.difference(DateTime.now());
      setState(() => _remaining = rem.isNegative ? Duration.zero : rem);
      if (rem.isNegative) _timer?.cancel();
    });
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _connect() async {
    final code = _codeController.text.trim().replaceAll(' ', '').toUpperCase();
    if (code.isEmpty) {
      setState(() => _errorMsg = 'Kodni kiriting');
      return;
    }

    setState(() {
      _connecting = true;
      _errorMsg = null;
    });

    final ds = context.read<DeviceService>();
    final ps = context.read<PeerService>();
    final myName = _nameController.text.trim().isEmpty ? ds.myDeviceName : _nameController.text.trim();

    // Join the room and announce presence
    await ps.joinChannel(code);
    ps.sendHello(myName);

    // Save device directly into paired list
    final device = await ds.addDevice(peerId: code, name: myName);
    ps.setTarget(device.id);

    // Give 1 second for handshake
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) {
        setState(() => _connecting = false);
        _showSuccessDialog("Ulanish muvaffaqiyatli saqlandi!");
      }
    });
  }

  void _showSuccessDialog(String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF12122A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Color(0xFF22C55E), size: 28),
            SizedBox(width: 10),
            Text('Ulandi!', style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: Text(
          message,
          style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: Color(0xFF6C63FF), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _showToast(String msg) {
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

  @override
  void dispose() {
    _timer?.cancel();
    _codeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          _buildHeader(),
          _buildTabs(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _showCode ? _buildShowCode() : _buildEnterCode(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() => const Padding(
    padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
    child: Center(
      child: Text(
        "Qurilma Qo'shish",
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white),
      ),
    ),
  );

  Widget _buildTabs() => Container(
    margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: const Color(0xFF12122A),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        _TabBtn(
          label: "Kodni Ko'rsat",
          icon: Icons.visibility_rounded,
          active: _showCode,
          onTap: () {
            setState(() => _showCode = true);
            final ds = context.read<DeviceService>();
            context.read<PeerService>().joinChannel(ds.currentCode);
          },
        ),
        _TabBtn(
          label: 'Kodni Kirit',
          icon: Icons.keyboard_rounded,
          active: !_showCode,
          onTap: () => setState(() => _showCode = false),
        ),
      ],
    ),
  );

  Widget _buildShowCode() {
    final ds = context.watch<DeviceService>();
    final code = ds.currentCode;

    return Column(
      children: [
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: const Color(0xFF12122A),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.3), width: 1.5),
          ),
          child: Column(
            children: [
              Text('Ulanish PIN kodi',
                style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.6))),
              const SizedBox(height: 14),

              // Large, super readable PIN code (e.g. 583 291)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF6C63FF).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.4)),
                ),
                child: Text(
                  code.length >= 6 ? '${code.substring(0, 3)}  ${code.substring(3)}' : code,
                  style: const TextStyle(
                    fontFamily: 'JetBrains Mono',
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4,
                    color: Color(0xFF00D4FF),
                  ),
                ),
              ),

              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.timer_outlined, size: 14, color: Colors.white.withOpacity(0.5)),
                  const SizedBox(width: 4),
                  Text('Muddati: ', style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.5))),
                  Text(_fmt(_remaining),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'JetBrains Mono',
                      color: _remaining.inSeconds < 60 ? const Color(0xFFEF4444) : const Color(0xFF22C55E),
                    )),
                ],
              ),
              const SizedBox(height: 18),

              // QR Code
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: code.isEmpty
                    ? const SizedBox(width: 140, height: 140)
                    : QrImageView(
                        data: code,
                        version: QrVersions.auto,
                        size: 140,
                      ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: code));
                        _showToast("PIN nusxalandi: $code");
                      },
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('Nusxalash'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(color: Colors.white.withOpacity(0.2)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _generateNewCode,
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Yangi PIN'),
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
        const SizedBox(height: 16),
        _buildInstructions(),
      ],
    );
  }

  Widget _buildInstructions() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFF12122A),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Ulanish juda oson:", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.9))),
        const SizedBox(height: 8),
        _InstrStep(num: 1, text: '2-telefonda "Kodni Kirit" bo\'limiga o\'ting'),
        _InstrStep(num: 2, text: 'Yuqoridagi PIN kodni kiriting (yoki nusxalab yuboring)'),
        _InstrStep(num: 3, text: '"Ulanish" tugmasini bosing — tayyor!'),
      ],
    ),
  );

  Widget _buildEnterCode() {
    return Column(
      children: [
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: const Color(0xFF12122A),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('PIN kodni yoki xona nomini kiriting',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.8))),
              const SizedBox(height: 12),

              // Super clean, large, robust text field with zero overflow issues
              TextField(
                controller: _codeController,
                textAlign: TextAlign.center,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF00D4FF),
                  letterSpacing: 3,
                ),
                decoration: InputDecoration(
                  hintText: 'Masalan: 482195',
                  hintStyle: TextStyle(
                    color: Colors.white.withOpacity(0.2),
                    fontSize: 18,
                    letterSpacing: 1,
                  ),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.06),
                  contentPadding: const EdgeInsets.symmetric(vertical: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFF6C63FF), width: 2),
                  ),
                ),
              ),

              const SizedBox(height: 16),
              Text('Sherik telefon nomi (ixtiyoriy)',
                style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.55))),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                maxLength: 20,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Masalan: 2-Telefonim 📱',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.06),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  counterText: '',
                ),
              ),

              if (_errorMsg != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_errorMsg!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12))),
                    ],
                  ),
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
                  label: Text(_connecting ? 'Ulanmoqda...' : 'Ulanish va Saqlash', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C63FF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    disabledBackgroundColor: const Color(0xFF6C63FF).withOpacity(0.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TabBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _TabBtn({required this.label, required this.icon, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF6C63FF) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: active ? Colors.white : Colors.white54),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
              color: active ? Colors.white : Colors.white54)),
          ],
        ),
      ),
    ),
  );
}

class _InstrStep extends StatelessWidget {
  final int num;
  final String text;
  const _InstrStep({required this.num, required this.text});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Container(
          width: 20, height: 20,
          decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF6C63FF).withOpacity(0.2),
            border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.4))),
          alignment: Alignment.center,
          child: Text('$num', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF6C63FF))),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.8)))),
      ],
    ),
  );
}
