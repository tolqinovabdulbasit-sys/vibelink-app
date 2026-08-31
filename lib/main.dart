import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'services/device_service.dart';
import 'services/vibration_service.dart';
import 'services/peer_service.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0A0A1A),
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => DeviceService()),
        ChangeNotifierProvider(create: (_) => VibrationService()),
        ChangeNotifierProvider(create: (_) => PeerService()),
      ],
      child: const VibeLinkApp(),
    ),
  );
}

class VibeLinkApp extends StatelessWidget {
  const VibeLinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VibeLink',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6C63FF),
          secondary: Color(0xFF00D4FF),
          surface: Color(0xFF12122A),
          error: Color(0xFFFF4757),
        ),
        scaffoldBackgroundColor: const Color(0xFF0A0A1A),
        fontFamily: 'Inter',
        textTheme: const TextTheme(
          displayLarge: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800),
          titleLarge: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700),
          bodyMedium: TextStyle(fontFamily: 'Inter'),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}
