# 📳 VibeLink

> **Masofaviy Real-Vaqtli Vibratsiya Boshqaruv Tizimi**

[![Build APK](https://github.com/tolqinovabdulbasit-sys/vibelink-app/actions/workflows/build-apk.yml/badge.svg)](https://github.com/tolqinovabdulbasit-sys/vibelink-app/actions/workflows/build-apk.yml)

## 📥 APK Yuklab Olish

**So'nggi versiya:**
👉 [Releases sahifasiga o'ting](https://github.com/tolqinovabdulbasit-sys/vibelink-app/releases) va APK ni yuklab oling.

**Build artefakti:**
👉 [Actions sahifasi](https://github.com/tolqinovabdulbasit-sys/vibelink-app/actions) → So'nggi workflow → Artifacts

## ✨ Imkoniyatlar

| Funksiya | Tavsif |
|----------|--------|
| 📳 **Jonli Rejim** | Tugmani bosib turganingizda sherik qurilma tebranadi |
| 📦 **8 Pattern** | Tayyor vibro-signallar to'plami |
| 🎨 **Pattern Studio** | Shaxsiy tebranish patternlarini yaratish |
| 🔗 **P2P Ulanish** | 8 xonali kod yoki QR orqali juftlash |
| 📊 **Tarix** | Barcha yuborilgan signallar tarixi |
| 🔒 **Xavfsiz** | Anonim ID, shifrlangan aloqa |

## 📱 Talablar

- Android **5.0+** (API 21+)
- Vibratsiya dvigateli
- Internet ulanish

## 🚀 Qurish

```bash
flutter pub get
flutter build apk --release
```

## 🏗️ Arxitektura

```
lib/
├── main.dart              # Kirish nuqtasi
├── screens/
│   ├── splash_screen.dart # Kirish ekrani
│   ├── home_screen.dart   # Bosh ekran
│   ├── pairing_screen.dart# Juftlash
│   ├── studio_screen.dart # Pattern tahrirlagichi
│   └── settings_screen.dart# Sozlamalar
├── services/
│   ├── peer_service.dart  # WebSocket P2P aloqa
│   ├── vibration_service.dart # Vibratsiya engine
│   └── device_service.dart# Qurilmalar boshqaruvi
├── models/
│   ├── device_model.dart  # Qurilma modeli
│   └── vibration_pattern.dart # Pattern modeli
└── widgets/              # Qayta ishlatiladigan komponentlar
```

---
Made with ❤️ by tolqinovabdulbasit-sys
